import Foundation

enum ReleaseDate {
    static func parse(_ string: String?) -> Date? {
        guard let string, string.utf8.count == 10 else { return nil }
        let parts = string.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              string.utf8.allSatisfy({ $0 == 45 || (48...57).contains($0) }),
              let year = Int(parts[0]), (1...9999).contains(year), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return date
    }

    static func string(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

struct LibraryPage: Sendable {
    let books: [BookProgress]
    let nextOffset: Int
    let hasMore: Bool
}

enum LibraryAPI {
    static let editionsQuery = """
    query EditionsForBook($bookId: Int!) {
      editions(
        where: {book_id: {_eq: $bookId}},
        order_by: [{users_count: desc_nulls_last}, {id: asc}]
      ) {
        id
        title
        isbn_10
        isbn_13
        pages
        audio_seconds
        release_date
        language { code2 language }
        publisher { name }
        image { url }
        reading_format { format }
      }
    }
    """
    static let fields = """
    id book_id status_id edition_id rating updated_at
    user_book_reads(order_by: {id: desc}, limit: 1) { id started_at finished_at progress_pages progress_seconds edition_id }
    book { id title rating release_date cached_contributors image { url } }
    edition { id title pages audio_seconds release_date reading_format { format } image { url } }
    """
    static let pageQuery = """
    query LibraryPage($userID: Int!, $status: Int!, $offset: Int!, $limit: Int!, $order: [user_books_order_by!]!) {
      user_books(where: {user_id: {_eq: $userID}, status_id: {_eq: $status}}, order_by: $order, offset: $offset, limit: $limit) {
        \(fields)
      }
    }
    """
    static let currentBookQuery = """
    query LibraryBook($userID: Int!, $bookID: Int!) {
      user_books(where: {user_id: {_eq: $userID}, book_id: {_eq: $bookID}}, order_by: {id: desc}, limit: 1) { \(fields) }
    }
    """
    static let identityQuery = "query SoftcoverIdentity { me { id username } }"

    static func request(_ query: String, variables: [String: Any] = [:], authorization: String? = nil, fresh: Bool = false, cost: Int = 1) async throws -> Data {
        let auth = authorization ?? HardcoverConfig.authorizationHeaderValue
        guard !auth.isEmpty else { throw HardcoverNetworkError.signIn }
        var request = URLRequest(url: URL(string: "https://api.hardcover.app/v1/graphql")!)
        request.httpMethod = "POST"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables], options: [.sortedKeys])
        let (data, _) = try await HardcoverHTTP.shared.data(for: request, cacheTTL: fresh ? 0 : 60, cost: cost)
        try Task.checkCancellation()
        if authorization == nil, auth != HardcoverConfig.authorizationHeaderValue { throw HardcoverNetworkError.accountChanged }
        return data
    }

    static func identity(authorization: String? = nil, fresh: Bool = false) async throws -> MeUser {
        let data = try await request(identityQuery, authorization: authorization, fresh: fresh)
        guard let user = try JSONDecoder().decode(GraphQLMeResponse.self, from: data).data?.me?.first else {
            throw HardcoverNetworkError.invalidResponse
        }
        return user
    }

    static func page(status: Int, offset: Int = 0, limit: Int = 50, username: String? = nil, fresh: Bool = false) async throws -> LibraryPage {
        guard offset >= 0, (1...100).contains(limit) else { throw HardcoverNetworkError.invalidResponse }
        let userID: Int
        if let username {
            let data = try await request("query LibraryUser($username: String!) { users(where: {username: {_eq: $username}}, limit: 1) { id username } }", variables: ["username": username])
            struct Response: Decodable { struct Value: Decodable { let users: [MeUser] }; let data: Value }
            guard let user = try JSONDecoder().decode(Response.self, from: data).data.users.first else { throw HardcoverNetworkError.invalidResponse }
            userID = user.id
        } else { userID = try await identity().id }
        let recentlyAdded = AppGroup.defaults.string(forKey: "CurrentlyReadingSortOrder") == "recentlyAdded"
        let order = status == 2 && !recentlyAdded ? [["updated_at": "desc"], ["id": "desc"]] : [["id": "desc"]]
        let data = try await request(pageQuery, variables: ["userID": userID, "status": status, "offset": offset, "limit": limit + 1, "order": order], fresh: fresh)
        guard let rows = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data).data?.user_books else {
            throw HardcoverNetworkError.invalidResponse
        }
        return LibraryPage(books: rows.prefix(limit).compactMap(makeBook), nextOffset: offset + min(limit, rows.count), hasMore: rows.count > limit)
    }

    static func ownBook(bookID: Int, fresh: Bool = false) async throws -> BookProgress? {
        let user = try await identity()
        let data = try await request(currentBookQuery, variables: ["userID": user.id, "bookID": bookID], fresh: fresh)
        guard let rows = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data).data?.user_books else { throw HardcoverNetworkError.invalidResponse }
        return rows.first.flatMap(makeBook)
    }

    static func makeBook(_ row: UserBook) -> BookProgress? {
        guard let source = row.book, let id = row.id else { return nil }
        let edition = row.edition
        let audio = edition?.isAudiobook ?? false
        let current = row.userBookReads?.first
        let total = audio ? edition?.totalMinutes ?? 0 : edition?.pages ?? 0
        let rawUnits = audio ? (current?.progressSeconds ?? 0) / 60 : current?.progressPages ?? 0
        let units = max(0, total > 0 ? min(rawUnits, total) : rawUnits)
        let release = edition?.releaseDate ?? source.releaseDate
        return BookProgress(
            id: String(id), title: (edition?.title?.isEmpty == false ? edition!.title! : source.title).decodedHTMLEntities,
            author: source.contributions?.compactMap { $0.author?.name }.joined(separator: ", ") ?? "",
            coverImageUrl: edition?.image?.url ?? source.image?.url,
            progress: total > 0 ? min(1, max(0, Double(units) / Double(total))) : 0,
            totalPages: edition?.pages ?? 0, currentPage: audio ? 0 : units,
            bookId: source.id, userBookId: id, editionId: row.editionId, originalTitle: source.title.decodedHTMLEntities,
            editionAverageRating: source.rating, userRating: row.rating, releaseDate: release,
            isAudiobook: audio, totalMinutes: edition?.totalMinutes ?? 0, currentMinute: audio ? units : 0,
            readingFormat: edition?.readingFormat?.format, statusId: row.statusId, parsedReleaseDate: ReleaseDate.parse(release)
        )
    }
}

enum LibrarySnapshot {
    struct Value: Codable { var books: [BookProgress]; let date: Date; let complete: Bool; var stale = false }
    private static func key(status: Int) -> String {
        "LibrarySnapshot.\(HardcoverRequestScheduler.accountKey(HardcoverConfig.authorizationHeaderValue)).\(status)"
    }
    static func load(status: Int, maxAge: TimeInterval = 86400) -> Value? {
        guard !HardcoverConfig.apiKey.isEmpty,
              let data = AppGroup.defaults.data(forKey: key(status: status)),
              let value = try? JSONDecoder().decode(Value.self, from: data), Date().timeIntervalSince(value.date) < maxAge else { return nil }
        return value
    }
    static func save(_ books: [BookProgress], status: Int, complete: Bool) {
        let lightweight = books.map { book in var copy = book; copy.coverImageData = nil; return copy }
        if let data = try? JSONEncoder().encode(Value(books: lightweight, date: Date(), complete: complete)) {
            AppGroup.defaults.set(data, forKey: key(status: status))
        }
    }
    static func clear() {
        for key in AppGroup.defaults.dictionaryRepresentation().keys where key.hasPrefix("LibrarySnapshot.") {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }

    static func invalidate(status: Int) {
        guard var value = load(status: status) else { return }
        value.stale = true
        if let data = try? JSONEncoder().encode(value) { AppGroup.defaults.set(data, forKey: key(status: status)) }
    }

    static func update(book: BookProgress) {
        for status in [1, 2, 3] {
            guard var value = load(status: status), let index = value.books.firstIndex(where: { $0.id == book.id }) else { continue }
            if let target = book.statusId, target != status { value.books.remove(at: index) }
            else {
                var lightweight = book
                lightweight.coverImageData = nil
                value.books[index] = lightweight
            }
            if let data = try? JSONEncoder().encode(value) { AppGroup.defaults.set(data, forKey: key(status: status)) }
        }
    }
}
