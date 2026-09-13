import Foundation

// Only platform/configuration dependencies are replaced. The network, scheduler,
// library, snapshots and Codable models are compiled from production source.
enum AppGroup {
    static let suiteName = "Softcover.AppCoreChecks.\(UUID().uuidString)"
    static let defaults = UserDefaults(suiteName: suiteName)!

    static func reset() { defaults.removePersistentDomain(forName: suiteName) }
    static func useAccount(_ name: String = UUID().uuidString) {
        defaults.set("test-only-\(name)", forKey: "HardcoverAPIKey")
    }
}

enum HardcoverConfig {
    static var apiKey: String { AppGroup.defaults.string(forKey: "HardcoverAPIKey") ?? "" }
    static var authorizationHeaderValue: String { apiKey.isEmpty ? "" : "Bearer \(apiKey)" }
}

extension String {
    // UIKit's HTML decoding is deliberately NOT under test in this executable.
    var decodedHTMLEntities: String { self }
}

struct AppCoreCheckFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw AppCoreCheckFailure(description: message) }
}

func requireError(_ message: String, matching predicate: (Error) -> Bool = { _ in true },
                  _ action: () async throws -> Void) async throws {
    do { try await action() }
    catch {
        try require(predicate(error), "\(message): unexpected \(error)")
        return
    }
    throw AppCoreCheckFailure(description: "\(message): unexpectedly succeeded")
}

func eventually(_ message: String, timeout: TimeInterval = 3,
                _ condition: () -> Bool) async throws {
    let end = Date().addingTimeInterval(timeout)
    while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(5)) }
    try require(condition(), message)
}

func eventuallyAsync(_ message: String, timeout: TimeInterval = 3,
                     _ condition: () async -> Bool) async throws {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw AppCoreCheckFailure(description: message)
}

final class AppCoreMockProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded: @unchecked Sendable {
        let request: URLRequest
        let body: [String: Any]
        var query: String { body["query"] as? String ?? "" }
        var variables: [String: Any] { body["variables"] as? [String: Any] ?? [:] }
    }

    struct Reply {
        var status = 200
        var data: Data
        var headers: [String: String] = [:]
        var delay: TimeInterval = 0

        init(_ json: [String: Any], status: Int = 200, headers: [String: String] = [:], delay: TimeInterval = 0) {
            self.status = status
            self.data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            self.headers = headers
            self.delay = delay
        }

        init(raw: String) { data = Data(raw.utf8) }
    }

    private static let lock = NSLock()
    private static var recorded: [Recorded] = []
    private static var stopped = 0
    private static var responder: (Recorded) throws -> Reply = { _ in
        throw AppCoreCheckFailure(description: "Unexpected request: no mock installed")
    }
    private let stateLock = NSLock()
    private var cancelled = false
    private var work: DispatchWorkItem?

    static var requests: [Recorded] { lock.withLock { recorded } }
    static var stoppedCount: Int { lock.withLock { stopped } }

    static func reset(_ handler: @escaping (Recorded) throws -> Reply) {
        lock.withLock { recorded = []; stopped = 0; responder = handler }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppCoreMockProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 3
        return URLSession(configuration: configuration)
    }

    // Capture every scheme/host, including unexpected traffic, rather than letting
    // unmatched requests escape to the network.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let entry = Recorded(request: request, body: body)
            let handler = Self.lock.withLock { Self.recorded.append(entry); return Self.responder }
            let reply = try handler(entry)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.stateLock.withLock({ self.cancelled }) else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: reply.data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            stateLock.withLock { work = item }
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: item)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {
        stateLock.withLock { cancelled = true; work?.cancel() }
        Self.lock.withLock { Self.stopped += 1 }
    }
}

func coreRequest(_ query: String = "query Probe { me { id username } }",
                 account: String = UUID().uuidString) throws -> URLRequest {
    var request = URLRequest(url: URL(string: "https://api.hardcover.app/v1/graphql")!)
    request.httpMethod = "POST"
    request.setValue("Bearer test-only-\(account)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query], options: [.sortedKeys])
    return request
}

func coreBook(id: Int = 1, audio: Bool = false, status: Int = 2) -> BookProgress {
    BookProgress(id: String(id), title: "Fixture \(id)", author: "Test Author", coverImageData: Data([1, 2, 3]),
                 totalPages: 240, currentPage: 60, bookId: id + 1000, userBookId: id,
                 editionId: id + 2000, originalTitle: "Fixture \(id)",
                 isAudiobook: audio, totalMinutes: 600, currentMinute: 120,
                 readingFormat: audio ? "Audio" : "Ebook", statusId: status)
}

func libraryRow(id: Int, format: String = "Ebook", seconds: Int = 3600,
                progressPages: Int = 80, progressSeconds: Int = 1200) -> [String: Any] {
    ["id": id, "book_id": id + 1000, "status_id": 2, "edition_id": id + 2000,
     "rating": 3.5, "updated_at": "2026-09-13T12:00:00Z",
     "user_book_reads": [["id": id + 3000, "progress_pages": progressPages,
                          "progress_seconds": progressSeconds, "edition_id": id + 2000]],
     "book": ["id": id + 1000, "title": "Original \(id)", "rating": 4.25,
              "release_date": "2024-02-29", "cached_contributors": [["author": ["name": "Test Author"]]],
              "image": ["url": "https://images.invalid/book.jpg"]],
     "edition": ["id": id + 2000, "title": "Edition \(id)", "pages": 240,
                 "audio_seconds": seconds, "release_date": "2026-09-01",
                 "reading_format": ["format": format], "image": ["url": "https://images.invalid/edition.jpg"]]]
}

func decodeRow(_ json: [String: Any]) throws -> UserBook {
    try JSONDecoder().decode(UserBook.self, from: JSONSerialization.data(withJSONObject: json))
}
