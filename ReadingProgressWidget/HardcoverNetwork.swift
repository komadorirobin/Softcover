import Foundation
import CryptoKit

enum HardcoverNetworkError: LocalizedError {
    case signIn, permission, invalidResponse, server(Int), graphQL(String), rateLimited(Date), accountChanged

    var errorDescription: String? {
        switch self {
        case .signIn: return NSLocalizedString("Connect a valid Hardcover API key in Settings.", comment: "")
        case .permission: return NSLocalizedString("Your API key does not have permission for this action.", comment: "")
        case .invalidResponse: return NSLocalizedString("Hardcover returned an unreadable response. Please try again.", comment: "")
        case .server(let status): return String(format: NSLocalizedString("Hardcover is unavailable (HTTP %d). Please try again.", comment: ""), status)
        case .graphQL(let message): return message
        case .rateLimited(let date):
            return String(format: NSLocalizedString("Hardcover is busy. Try again after %@.", comment: ""), date.formatted(date: .omitted, time: .shortened))
        case .accountChanged: return NSLocalizedString("The connected account changed. Please try again.", comment: "")
        }
    }
}

// Carries transport errors through older optional-returning read APIs during migration.
final class HardcoverReadFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?
    func record(_ error: Error) { lock.lock(); defer { lock.unlock() }; if stored == nil { stored = error } }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return stored }
}

enum HardcoverReadScope {
    @TaskLocal static var failure: HardcoverReadFailure?

    static func checked<T>(_ action: () async -> T) async throws -> T {
        let failure = HardcoverReadFailure()
        let result = await $failure.withValue(failure) { await action() }
        try Task.checkCancellation()
        if let error = failure.error { throw error }
        return result
    }
}

actor HardcoverRequestScheduler {
    static let shared = HardcoverRequestScheduler()
    struct Bucket {
        var available = 5.0
        var capacity = 5.0
        var rate = 1.0
        var updated = Date()
        var blockedUntil = Date.distantPast
    }
    private var buckets: [String: Bucket] = [:]

    func acquire(authorization: String, cost: Int = 1) async throws {
        guard !authorization.isEmpty else { throw HardcoverNetworkError.signIn }
        let key = Self.accountKey(authorization)
        while true {
            try Task.checkCancellation()
            let now = Date()
            var bucket = buckets[key] ?? Bucket()
            bucket.available = min(bucket.capacity, bucket.available + max(0, now.timeIntervalSince(bucket.updated)) * bucket.rate)
            bucket.updated = now
            let delay = max(bucket.blockedUntil.timeIntervalSince(now), (Double(cost) - bucket.available) / bucket.rate)
            if delay <= 0 {
                bucket.available -= Double(cost)
                buckets[key] = bucket
                return
            }
            buckets[key] = bucket
            if delay > 30 { throw HardcoverNetworkError.rateLimited(now.addingTimeInterval(delay)) }
            try await Task.sleep(for: .seconds(max(0.05, delay)))
        }
    }

    func observe(_ response: HTTPURLResponse, authorization: String) {
        let key = Self.accountKey(authorization)
        var bucket = buckets[key] ?? Bucket()
        if let policy = response.value(forHTTPHeaderField: "RateLimit-Policy") {
            let first = policy.components(separatedBy: ",").first ?? policy
            let fields = Self.fields(first)
            if let burst = fields["burst"] { bucket.capacity = max(1, burst) }
            if let quota = fields["q"], let window = fields["w"], window > 0 { bucket.rate = max(0.01, quota / window) }
        }
        if let value = response.value(forHTTPHeaderField: "RateLimit") {
            for part in value.components(separatedBy: ",") {
                let fields = Self.fields(part)
                if part.contains("daily"), fields["r"] == 0, let seconds = fields["t"] {
                    bucket.blockedUntil = max(bucket.blockedUntil, Date().addingTimeInterval(seconds))
                } else if !part.contains("daily"), let remaining = fields["r"] {
                    bucket.available = min(bucket.available, max(0, remaining))
                }
            }
        }
        if response.statusCode == 429 {
            bucket.blockedUntil = max(bucket.blockedUntil, Self.retryDate(response))
            bucket.available = 0
        }
        buckets[key] = bucket
    }

    static func retryDate(_ response: HTTPURLResponse) -> Date {
        let value = response.value(forHTTPHeaderField: "Retry-After") ?? ""
        if let seconds = Double(value) { return Date().addingTimeInterval(max(1, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value) ?? Date().addingTimeInterval(60)
    }

    private static func fields(_ value: String) -> [String: Double] {
        Dictionary(value.components(separatedBy: ";").compactMap { item -> (String, Double)? in
            let pair = item.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let number = Double(pair[1]) else { return nil }
            return (pair[0], number)
        }, uniquingKeysWith: { _, last in last })
    }

    static func accountKey(_ authorization: String) -> String {
        SHA256.hash(data: Data(authorization.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

actor HardcoverHTTP {
    static let shared = HardcoverHTTP()
    private struct Cached {
        let data: Data
        let response: URLResponse
        let expires: Date
        let account: String
    }
    private struct Pending {
        let id: UUID
        let account: String
        let task: Task<(Data, URLResponse), Error>
        var waiters: Set<UUID>
    }
    private var cache: [String: Cached] = [:]
    private var pending: [String: Pending] = [:]
    private var revision = 0
    private var readRevisions: [String: Int] = [:]
    let session: URLSession
    let scheduler: HardcoverRequestScheduler

    #if SOFTCOVER_CORE_TESTS
    var pendingReaderCount: Int { pending.values.reduce(0) { $0 + $1.waiters.count } }
    #endif

    init(session: URLSession = .shared, scheduler: HardcoverRequestScheduler = .shared) {
        self.session = session
        self.scheduler = scheduler
    }

    func invalidate() {
        revision += 1
        cache.removeAll()
        for entry in pending.values { entry.task.cancel() }
        pending.removeAll()
    }

    func invalidateReads(authorization: String) {
        let account = HardcoverRequestScheduler.accountKey(authorization)
        readRevisions[account, default: 0] += 1
        cache = cache.filter { $0.value.account != account }
        for (key, entry) in pending where entry.account == account {
            entry.task.cancel()
            pending[key] = nil
        }
    }

    func data(for request: URLRequest, cacheTTL: TimeInterval = 30, cost: Int = 1) async throws -> (Data, URLResponse) {
        do { return try await perform(request, cacheTTL: cacheTTL, cost: cost) }
        catch {
            let failure: Error = Task.isCancelled || (error as? URLError)?.code == .cancelled ? CancellationError() : error
            HardcoverReadScope.failure?.record(failure)
            throw failure
        }
    }

    private func cancelWaiter(key: String, waiter: UUID) {
        guard var entry = pending[key] else { return }
        entry.waiters.remove(waiter)
        if entry.waiters.isEmpty {
            entry.task.cancel()
            pending[key] = nil
        } else { pending[key] = entry }
    }

    private func perform(_ original: URLRequest, cacheTTL: TimeInterval, cost: Int) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        var request = original
        request.timeoutInterval = min(request.timeoutInterval, 35)
        request.setValue("Softcover/iOS", forHTTPHeaderField: "User-Agent")
        let isGraphQL = request.url?.host == "api.hardcover.app"
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let account = HardcoverRequestScheduler.accountKey(authorization)
        let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let query = payload?["query"] as? String ?? ""
        let readOnly = request.httpMethod == "GET" || query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("query") || query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
        let identity = Data((account + (request.url?.absoluteString ?? "") + (request.httpMethod ?? "GET")).utf8) + (request.httpBody ?? Data())
        let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        if readOnly, cacheTTL > 0, let hit = cache[key], hit.expires > Date() { return (hit.data, hit.response) }
        let currentRevision = revision
        let readRevision = readRevisions[account, default: 0]
        let pendingKey = readOnly && cacheTTL > 0 ? key : UUID().uuidString
        let waiter = UUID()
        let entry: Pending
        if readOnly, cacheTTL > 0, var existing = pending[pendingKey] {
            existing.waiters.insert(waiter)
            pending[pendingKey] = existing
            entry = existing
        } else {
            let session = self.session
            let scheduler = self.scheduler
            entry = Pending(id: UUID(), account: account, task: Task {
                if isGraphQL { try await scheduler.acquire(authorization: authorization, cost: cost) }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw HardcoverNetworkError.invalidResponse }
                if isGraphQL { await scheduler.observe(http, authorization: authorization) }
                switch http.statusCode {
                case 200..<300: break
                case 401: throw HardcoverNetworkError.signIn
                case 403: throw HardcoverNetworkError.permission
                case 429: throw HardcoverNetworkError.rateLimited(HardcoverRequestScheduler.retryDate(http))
                default: throw HardcoverNetworkError.server(http.statusCode)
                }
                if isGraphQL {
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw HardcoverNetworkError.invalidResponse
                    }
                    if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
                        throw HardcoverNetworkError.graphQL(errors.compactMap { $0["message"] as? String }.joined(separator: "\n"))
                    }
                    guard root["data"] is [String: Any] else { throw HardcoverNetworkError.invalidResponse }
                }
                return (data, response)
            }, waiters: [waiter])
            if readOnly { pending[pendingKey] = entry }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await entry.task.value
            } onCancel: {
                if readOnly { Task { await self.cancelWaiter(key: pendingKey, waiter: waiter) } }
            }
            if pending[pendingKey]?.id == entry.id { pending[pendingKey] = nil }
            // A confirmed write changes server state even when its observing view has gone away.
            if !readOnly { invalidateReads(authorization: authorization) }
            try Task.checkCancellation()
            guard currentRevision == revision else { throw HardcoverNetworkError.accountChanged }
            if readOnly, readRevision != readRevisions[account, default: 0] { throw CancellationError() }
            if readOnly, cacheTTL > 0 {
                cache = cache.filter { $0.value.expires > Date() }
                if cache.count > 150 { cache.removeAll() }
                cache[key] = Cached(data: result.0, response: result.1, expires: Date().addingTimeInterval(cacheTTL), account: account)
            }
            return result
        } catch {
            if pending[pendingKey]?.id == entry.id { pending[pendingKey] = nil }
            throw error
        }
    }
}
