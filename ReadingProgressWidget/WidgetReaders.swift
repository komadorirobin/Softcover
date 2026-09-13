import Foundation

struct WidgetLoad<Value: Sendable>: Sendable {
    let value: Value
    let date: Date
    let failed: Bool
}

enum WidgetReaders {
    static func reading(selectedIDs: [String] = []) async -> WidgetLoad<[BookProgress]> {
        let selected = Array(selectedIDs.prefix(4))
        if !selected.isEmpty {
            let variant = HardcoverRequestScheduler.accountKey(selected.joined(separator: ","))
            let loaded: WidgetLoad<[BookProgress]> = await load(kind: WidgetSync.readingKind, variant: variant, freshFor: 300, fallback: []) {
                var books = try await selectedBooks(ids: selected)
                await HardcoverService.loadImagesForWidgets(books: &books)
                return books
            }
            return await readingFallback(loaded, selectedIDs: selected)
        }
        let token = WidgetSnapshotStore.token(kind: WidgetSync.readingKind)
        // App Group progress can be newer than the widget's own last-good snapshot.
        if let library = LibrarySnapshot.load(status: 2, maxAge: 300), !library.stale {
            let books = await HardcoverService.fetchCurrentlyReading(forWidget: true)
            guard token == WidgetSnapshotStore.token(kind: token.kind) else { return .init(value: [], date: Date(), failed: true) }
            WidgetSnapshotStore.save(books, token: token, date: library.date)
            return .init(value: books, date: library.date, failed: false)
        }
        let loaded: WidgetLoad<[BookProgress]> = await load(kind: WidgetSync.readingKind, freshFor: 300, fallback: []) {
            try await HardcoverReadScope.checked { await HardcoverService.fetchCurrentlyReading(forWidget: true) }
        }
        return await readingFallback(loaded, selectedIDs: [])
    }

    private static func readingFallback(_ loaded: WidgetLoad<[BookProgress]>, selectedIDs: [String]) async -> WidgetLoad<[BookProgress]> {
        guard loaded.failed, loaded.value.isEmpty,
              let library = LibrarySnapshot.load(status: 2, maxAge: 86400) else { return loaded }
        let token = WidgetSnapshotStore.token(kind: WidgetSync.readingKind)
        let byID = Dictionary(library.books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var books = selectedIDs.isEmpty ? Array(library.books.prefix(10)) : selectedIDs.compactMap { byID[$0] }
        await HardcoverService.loadImagesForWidgets(books: &books)
        guard token == WidgetSnapshotStore.token(kind: token.kind) else { return .init(value: [], date: Date(), failed: true) }
        return .init(value: books, date: library.date, failed: true)
    }

    static func selectedBooks(ids: [String]) async throws -> [BookProgress] {
        let ids = Array(ids.prefix(100))
        guard !ids.isEmpty else { return [] }
        if let snapshot = LibrarySnapshot.load(status: 2, maxAge: 300), !snapshot.stale {
            let byID = Dictionary(snapshot.books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let matches = ids.compactMap { byID[$0] }
            if snapshot.complete || matches.count == ids.count { return matches }
        }
        let user = try await LibraryAPI.identity()
        let data = try await LibraryAPI.request(selectedBooksQuery, variables: ["userID": user.id, "ids": ids.compactMap(Int.init)])
        guard let rows = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data).data?.user_books else {
            throw HardcoverNetworkError.invalidResponse
        }
        let books = rows.compactMap(LibraryAPI.makeBook)
        let byID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    static let selectedBooksQuery = """
    query WidgetSelectedBooks($userID: Int!, $ids: [Int!]!) {
      user_books(where: {user_id: {_eq: $userID}, id: {_in: $ids}, status_id: {_eq: 2}}, limit: 100) {
        \(LibraryAPI.fields)
      }
    }
    """

    static func goals() async -> WidgetLoad<[ReadingGoal]> {
        await load(kind: WidgetSync.goalKind, freshFor: 900, fallback: []) {
            let goals = try await HardcoverReadScope.checked { await HardcoverService.fetchReadingGoals() }
            return Array(goals.prefix(100))
        }
    }

    static func releases() async -> WidgetLoad<[CachedWidgetRelease]> {
        let loaded = await load(kind: WidgetSync.upcomingKind, freshFor: 3600, fallback: [CachedWidgetRelease]()) {
            let releases = try await HardcoverReadScope.checked {
                await HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: 30)
            }
            return releases.map(CachedWidgetRelease.init)
        }
        let today = Calendar.current.startOfDay(for: Date())
        return .init(value: loaded.value.filter { $0.releaseDate >= today }, date: loaded.date, failed: loaded.failed)
    }

    static func quotes() async -> WidgetLoad<[HardcoverService.ReadingJournalQuote]> {
        await load(kind: WidgetSync.quoteKind, freshFor: 3600, fallback: []) {
            let user = try await LibraryAPI.identity()
            let data = try await LibraryAPI.request(quoteQuery, variables: ["userID": user.id])
            // Sample the whole journal, not just its newest entries, then bound the cache.
            return Array(try decodeQuotes(data).shuffled().prefix(250))
        }
    }

    static let quoteQuery = """
    query WidgetQuotes($userID: Int!) {
      reading_journals(where: {user_id: {_eq: $userID}, event: {_eq: "quote"}}, order_by: {id: desc}) {
        id entry book_id created_at
        book { title contributions { author { name } } }
      }
    }
    """

    static func decodeQuotes(_ data: Data) throws -> [HardcoverService.ReadingJournalQuote] {
        struct Response: Decodable {
            struct Value: Decodable { let reading_journals: [HardcoverService.ReadingJournalQuote] }
            let data: Value
        }
        return try JSONDecoder().decode(Response.self, from: data).data.reading_journals
    }

    private static func load<Value: Codable & Sendable>(kind: String, variant: String = "", freshFor: TimeInterval, fallback: Value, fetch: @escaping @Sendable () async throws -> Value) async -> WidgetLoad<Value> {
        guard !HardcoverConfig.apiKey.isEmpty else { return .init(value: fallback, date: Date(), failed: false) }
        let token = WidgetSnapshotStore.token(kind: kind, variant: variant)
        if let cached = WidgetSnapshotStore.load(Value.self, token: token, maxAge: freshFor, fresh: true) {
            return .init(value: cached.payload, date: cached.date, failed: false)
        }
        do {
            let data = try await WidgetReadCoalescer.shared.data(token: token) {
                try JSONEncoder().encode(await fetch())
            }
            guard token == WidgetSnapshotStore.token(kind: kind, variant: variant), !HardcoverConfig.apiKey.isEmpty else {
                return .init(value: fallback, date: Date(), failed: true)
            }
            let value = try JSONDecoder().decode(Value.self, from: data)
            WidgetSnapshotStore.save(value, token: token)
            return .init(value: value, date: Date(), failed: false)
        } catch {
            let previous = WidgetSnapshotStore.load(Value.self, token: token, maxAge: 86400)
            return .init(value: previous?.payload ?? fallback, date: previous?.date ?? Date(), failed: true)
        }
    }
}

struct CachedWidgetRelease: Codable, Sendable {
    let id: Int
    let bookId: Int?
    let title: String
    let author: String
    let releaseDate: Date
    let coverImageData: Data?

    init(_ release: HardcoverService.UpcomingRelease) {
        id = release.id
        bookId = release.bookId
        title = release.title
        author = release.author
        releaseDate = release.releaseDate
        coverImageData = release.coverImageData
    }

    var release: HardcoverService.UpcomingRelease {
        .init(id: id, bookId: bookId, title: title, author: author, releaseDate: releaseDate, coverImageData: coverImageData)
    }
}

private actor WidgetReadCoalescer {
    static let shared = WidgetReadCoalescer()
    private var inFlight: [WidgetSnapshotStore.Token: Task<Data, Error>] = [:]
    private var failures: [WidgetSnapshotStore.Token: (date: Date, error: Error)] = [:]

    func data(token: WidgetSnapshotStore.Token, fetch: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let task = inFlight[token] { return try await task.value }
        if let failed = failures[token], Date().timeIntervalSince(failed.date) < 60 { throw failed.error }
        let task = Task { try await fetch() }
        inFlight[token] = task
        defer { inFlight[token] = nil }
        do {
            let data = try await task.value
            failures[token] = nil
            return data
        } catch {
            failures = failures.filter { Date().timeIntervalSince($0.value.date) < 60 }
            failures[token] = (Date(), error)
            throw error
        }
    }
}
