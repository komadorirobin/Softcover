import Foundation
import WidgetKit

extension Notification.Name {
    static let libraryDidChange = Notification.Name("BookListsNeedRefresh")
}

enum WidgetSync {
    static let readingKind = "ReadingProgressWidget"
    static let goalKind = "ReadingGoalWidget"
    static let upcomingKind = "ReleaseCountdownWidget"
    static let quoteKind = "QuoteWidget"
    static let allKinds: Set<String> = [readingKind, goalKind, upcomingKind, quoteKind]

    private static let coordinator = WidgetReloadCoordinator(
        reload: { WidgetCenter.shared.reloadTimelines(ofKind: $0) },
        notify: { statuses in
            NotificationCenter.default.post(name: .libraryDidChange, object: nil, userInfo: ["statuses": statuses])
        }
    )

    static func libraryChanged(statuses: [Int]) {
        let affected = Set(statuses)
        for status in affected { LibrarySnapshot.invalidate(status: status) }
        let kinds = kindsForLibraryChange(statuses: affected)
        for kind in kinds { WidgetSnapshotStore.invalidate(kind: kind) }
        coordinator.request(kinds: kinds, statuses: affected)
    }

    static func progressChanged(book: BookProgress) {
        // Patch before requesting a timeline, without claiming the entire list is fresh.
        LibrarySnapshot.update(book: book)
        WidgetSnapshotStore.invalidate(kind: readingKind)
        WidgetSnapshotStore.updateReading(book: book)
        WidgetSnapshotStore.invalidate(kind: goalKind)
        coordinator.request(kinds: [readingKind, goalKind], statuses: [book.statusId ?? 2])
    }

    static func accountChanged() {
        LibrarySnapshot.clear()
        WidgetSnapshotStore.clear()
        coordinator.request(kinds: allKinds, statuses: [1, 2, 3], reset: true)
    }

    static func quotesChanged() {
        WidgetSnapshotStore.invalidate(kind: quoteKind)
        coordinator.request(kinds: [quoteKind])
    }

    static func goalsChanged() {
        WidgetSnapshotStore.invalidate(kind: goalKind)
        coordinator.request(kinds: [goalKind])
    }

    static func kindsForLibraryChange(statuses: Set<Int>) -> Set<String> {
        var kinds: Set<String> = []
        if statuses.contains(1) { kinds.insert(upcomingKind) }
        if statuses.contains(2) { kinds.insert(readingKind) }
        if !statuses.isDisjoint(with: [2, 3]) { kinds.insert(goalKind) }
        return kinds
    }
}

// One short, bounded batch per process; WidgetKit decides when requests actually run.
final class WidgetReloadCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private let reload: @Sendable (String) -> Void
    private let notify: @Sendable ([Int]) -> Void
    private var kinds: Set<String> = []
    private var statuses: Set<Int> = []
    private var scheduled = false

    init(delay: TimeInterval = 0.35, reload: @escaping @Sendable (String) -> Void, notify: @escaping @Sendable ([Int]) -> Void) {
        self.delay = delay
        self.reload = reload
        self.notify = notify
    }

    func request(kinds: Set<String>, statuses: Set<Int> = [], reset: Bool = false) {
        lock.lock()
        if reset { self.kinds.removeAll(); self.statuses.removeAll() }
        self.kinds.formUnion(kinds)
        self.statuses.formUnion(statuses)
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if shouldSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.flush() }
        }
    }

    func flush() {
        lock.lock()
        let pendingKinds = kinds
        let pendingStatuses = statuses
        kinds.removeAll()
        statuses.removeAll()
        scheduled = false
        lock.unlock()
        for kind in pendingKinds.sorted() { reload(kind) }
        if !pendingStatuses.isEmpty { notify(pendingStatuses.sorted()) }
    }
}

enum WidgetDeepLink {
    static func goal(id: Int?) -> URL {
        make(host: "goals", items: id.map { [URLQueryItem(name: "goalId", value: String($0))] } ?? [])
    }

    static func upcoming(bookID: Int?, editionID: Int?) -> URL {
        var items: [URLQueryItem] = []
        if let bookID { items.append(URLQueryItem(name: "bookId", value: String(bookID))) }
        if let editionID { items.append(URLQueryItem(name: "editionId", value: String(editionID))) }
        return make(host: "upcoming", items: items)
    }

    private static func make(host: String, items: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "softcover"
        components.host = host
        if !items.isEmpty { components.queryItems = items }
        return components.url!
    }
}

enum WidgetSnapshotStore {
    struct Token: Hashable, Sendable {
        let account: String
        let kind: String
        let generation: String
        let variant: String
    }

    struct Value<Payload: Codable>: Codable {
        let payload: Payload
        let date: Date
        let generation: String
    }

    private static let prefix = "WidgetSnapshot.v1."
    private static let maximumBytes = 2 * 1024 * 1024
    private static let lock = NSRecursiveLock()

    static func token(kind: String, variant: String = "") -> Token {
        lock.lock()
        defer { lock.unlock() }
        let account = HardcoverRequestScheduler.accountKey(HardcoverConfig.authorizationHeaderValue)
        let generation = AppGroup.defaults.string(forKey: "\(prefix)\(account).\(kind).generation") ?? "initial"
        return Token(account: account, kind: kind, generation: generation, variant: variant)
    }

    static func load<Payload: Codable>(_ type: Payload.Type, token: Token, maxAge: TimeInterval, fresh: Bool = false) -> Value<Payload>? {
        lock.lock()
        defer { lock.unlock() }
        let current = self.token(kind: token.kind, variant: token.variant)
        guard !HardcoverConfig.apiKey.isEmpty, token.account == self.token(kind: token.kind).account,
              let data = AppGroup.defaults.data(forKey: key(token)), data.count <= maximumBytes,
              let value = try? JSONDecoder().decode(Value<Payload>.self, from: data),
              Date().timeIntervalSince(value.date) >= 0, Date().timeIntervalSince(value.date) < maxAge,
              !fresh || (value.generation == token.generation && token == current) else { return nil }
        return value
    }

    @discardableResult
    static func save<Payload: Codable>(_ payload: Payload, token: Token, date: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !HardcoverConfig.apiKey.isEmpty, token == self.token(kind: token.kind, variant: token.variant),
              let data = try? JSONEncoder().encode(Value(payload: payload, date: date, generation: token.generation)),
              data.count <= maximumBytes else { return false }
        AppGroup.defaults.set(data, forKey: key(token))
        trim(account: token.account)
        return true
    }

    static func invalidate(kind: String) {
        lock.lock()
        defer { lock.unlock() }
        let token = token(kind: kind)
        AppGroup.defaults.set(UUID().uuidString, forKey: "\(key(token)).generation")
    }

    static func updateReading(book: BookProgress) {
        lock.lock()
        defer { lock.unlock() }
        let token = token(kind: WidgetSync.readingKind)
        let readingPrefix = key(token)
        for key in AppGroup.defaults.dictionaryRepresentation().keys where key == readingPrefix || key.hasPrefix(readingPrefix + ".variant.") {
            guard let data = AppGroup.defaults.data(forKey: key), data.count <= maximumBytes,
                  let value = try? JSONDecoder().decode(Value<[BookProgress]>.self, from: data),
                  let index = value.payload.firstIndex(where: { $0.id == book.id }) else { continue }
            var books = value.payload
            var updated = book
            if updated.coverImageData == nil, updated.coverImageUrl == books[index].coverImageUrl {
                updated.coverImageData = books[index].coverImageData
            }
            books[index] = updated
            // A local patch is not a successful refresh of the complete server response.
            let patched = Value(payload: books, date: value.date, generation: value.generation)
            if let data = try? JSONEncoder().encode(patched), data.count <= maximumBytes,
               token == self.token(kind: token.kind) {
                AppGroup.defaults.set(data, forKey: key)
            }
        }
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        for key in AppGroup.defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            AppGroup.defaults.removeObject(forKey: key)
        }
        // Block any result that began before this reset, even when signing back into the same account.
        for kind in WidgetSync.allKinds { invalidate(kind: kind) }
    }

    private static func key(_ token: Token) -> String {
        let base = "\(prefix)\(token.account).\(token.kind)"
        return token.variant.isEmpty ? base : "\(base).variant.\(token.variant)"
    }

    private static func trim(account: String) {
        struct Header: Decodable { let date: Date }
        let accountPrefix = "\(prefix)\(account)."
        let candidates = AppGroup.defaults.dictionaryRepresentation().compactMap { key, value -> (String, Date)? in
            guard key.hasPrefix(accountPrefix), let data = value as? Data,
                  let header = try? JSONDecoder().decode(Header.self, from: data) else { return nil }
            return (key, header.date)
        }
        // Four ordinary feeds plus a bounded number of manual-selection variants.
        for (key, _) in candidates.sorted(by: { $0.1 > $1.1 }).dropFirst(12) {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }
}
