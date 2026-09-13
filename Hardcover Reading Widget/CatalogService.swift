import Foundation

actor CatalogRequestGate {
    static let shared = CatalogRequestGate()
    private var deadlines: [String: Date] = [:]

    func deadline(for authorization: String, now: Date) -> Date? {
        guard let date = deadlines[authorization], date > now else { return nil }
        return date
    }

    func deferRequests(for authorization: String, until date: Date, now: Date) {
        deadlines = deadlines.filter { $0.value > now }
        deadlines[authorization] = max(deadlines[authorization] ?? date, date)
    }
}

struct CatalogService {
    let authorization: String
    var session: URLSession = .shared
    var currentAuthorization: () -> String
    var requestGate = CatalogRequestGate.shared
    var now: () -> Date = Date.init
    var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    var onRateLimit: (Date?) async -> Void = { _ in }
    var beforeRequest: (String) async throws -> Void = { _ in }
    var afterResponse: (HTTPURLResponse) async -> Void = { _ in }
    var afterMutation: () async -> Void = {}

    private struct Envelope<T: Decodable>: Decodable {
        let data: T?
        let errors: [APIError]?
    }
    private struct APIError: Decodable { let message: String }
    private struct MeResponse: Decodable {
        struct Me: Decodable { let roles: CatalogRoles }
        let me: [Me]
    }
    private struct BookResponse: Decodable { let book: CatalogBook? }
    private struct EditionResponse: Decodable { let edition: CatalogEdition? }
    private struct OverviewResponse: Decodable {
        struct Book: Decodable {
            let details: CatalogBook
            let editions: [CatalogEditionSummary]
            private enum CodingKeys: String, CodingKey { case editions }
            init(from decoder: Decoder) throws {
                details = try CatalogBook(from: decoder)
                editions = try decoder.container(keyedBy: CodingKeys.self).decode([CatalogEditionSummary].self, forKey: .editions)
            }
        }
        let me: [MeResponse.Me]
        let book: Book?
    }
    private struct EditionEditingResponse: Decodable {
        let edition: CatalogEdition?
        let formats: [CatalogFormat]
        let roles: [CatalogEntity]
    }
    private struct EditionsResponse: Decodable { let editions: [CatalogEditionSummary] }
    private struct SearchResponse: Decodable {
        struct Search: Decodable { let ids: [Int]?; let error: String? }
        let search: Search?
    }
    private struct EntitiesResponse: Decodable { let entities: [CatalogEntity] }
    private struct MutationResponse: Decodable {
        struct Result: Decodable { let id: Int?; let errors: [String]?; let warnings: [String]? }
        let result: Result?
    }

    static let contributionFields = """
    id authorID: author_id author { id name } contribution
    roleID: contributor_role_id specializationID: contributor_specialization_id
    """
    static let editionSummaryFields = """
    id title isbn13: isbn_13 readingFormat: reading_format { id format } image { id url }
    """
    static let bookFields = """
        id title description releaseDate: release_date locked image { id url }
        defaultCoverEditionID: default_cover_edition_id
        defaultCoverEdition: default_cover_edition { \(editionSummaryFields) }
        contributions(order_by: {id: asc}) { \(contributionFields) }
        series: book_series(order_by: {id: asc}) {
          id seriesID: series_id series { id name } position details featured compilation
        }
    """
    static let bookQuery = """
    query CatalogBook($id: Int!) {
      book: books_by_pk(id: $id) { \(bookFields) }
    }
    """
    static let overviewQuery = """
    query CatalogOverview($id: Int!) {
      me { roles: librarian_roles }
      book: books_by_pk(id: $id) {
        \(bookFields)
        editions(order_by: [{users_count: desc_nulls_last}, {id: asc}], limit: 50) {
          \(editionSummaryFields)
        }
      }
    }
    """
    static let editionFields = """
        id bookID: book_id title subtitle isbn10: isbn_10 isbn13: isbn_13 pages
        audioSeconds: audio_seconds releaseDate: release_date locked
        readingFormatID: reading_format_id editionFormat: edition_format
        publisher { id name } image { id url } images(order_by: {id: asc}) { id url }
        contributions(order_by: {id: asc}) { \(contributionFields) }
    """
    static let editionQuery = """
    query CatalogEdition($id: Int!) {
      edition: editions_by_pk(id: $id) { \(editionFields) }
    }
    """
    static let editionEditingQuery = """
    query CatalogEditionEditing($id: Int!) {
      edition: editions_by_pk(id: $id) { \(editionFields) }
      formats: reading_formats(order_by: {id: asc}) { id format }
      roles: contributor_roles(order_by: {name: asc}) { id name }
    }
    """
    static let editionsQuery = """
    query CatalogEditions($bookID: Int!, $offset: Int!) {
      editions(where: {book_id: {_eq: $bookID}}, order_by: [{users_count: desc_nulls_last}, {id: asc}], limit: 50, offset: $offset) {
        \(editionSummaryFields)
      }
    }
    """
    static let rolesQuery = "query CatalogRoles { me { roles: librarian_roles } }"
    static let lookupsQuery = """
    query CatalogLookups {
      formats: reading_formats(order_by: {id: asc}) { id format }
      roles: contributor_roles(order_by: {name: asc}) { id name }
    }
    """
    static let searchQuery = """
    query CatalogSearch($query: String!, $type: String!, $page: Int!) {
      search(query: $query, query_type: $type, page: $page, per_page: 25) { ids error }
    }
    """
    static let updateBookMutation = """
    mutation EditCatalogBook($id: Int!, $input: BookInput!) {
      result: update_book(id: $id, book: $input) { id errors warnings }
    }
    """
    static let updateEditionMutation = """
    mutation EditCatalogEdition($id: Int!, $input: EditionInput!) {
      result: update_edition(id: $id, edition: $input) { id errors warnings }
    }
    """
    static let importImageMutation = """
    mutation ImportCatalogCover($image: ImageInput!) {
      result: insert_image(image: $image) { id }
    }
    """

    func canEdit() async throws -> Bool {
        let response: MeResponse = try await request(Self.rolesQuery)
        guard let me = response.me.first else { throw CatalogError.permission }
        return me.roles.canEdit
    }

    func requireLibrarian() async throws {
        guard try await canEdit() else { throw CatalogError.permission }
    }

    func book(id: Int) async throws -> CatalogBook {
        let response: BookResponse = try await request(Self.bookQuery, variables: ["id": id])
        guard let book = response.book else { throw CatalogError.invalidResponse }
        return book
    }

    func editorOverview(bookID: Int) async throws -> (book: CatalogBook, editions: [CatalogEditionSummary]) {
        let response: OverviewResponse = try await request(Self.overviewQuery, variables: ["id": bookID])
        guard response.me.first?.roles.canEdit == true else { throw CatalogError.permission }
        guard let book = response.book else { throw CatalogError.invalidResponse }
        return (book.details, book.editions)
    }

    func editionEditingData(id: Int) async throws -> (edition: CatalogEdition, lookups: CatalogLookups) {
        let response: EditionEditingResponse = try await request(Self.editionEditingQuery, variables: ["id": id])
        guard let edition = response.edition else { throw CatalogError.invalidResponse }
        return (edition, CatalogLookups(formats: response.formats, roles: response.roles))
    }

    func edition(id: Int) async throws -> CatalogEdition {
        let response: EditionResponse = try await request(Self.editionQuery, variables: ["id": id])
        guard let edition = response.edition else { throw CatalogError.invalidResponse }
        return edition
    }

    func editions(bookID: Int, offset: Int = 0) async throws -> [CatalogEditionSummary] {
        let response: EditionsResponse = try await request(Self.editionsQuery, variables: ["bookID": bookID, "offset": offset])
        return response.editions
    }

    func lookups() async throws -> CatalogLookups { try await request(Self.lookupsQuery) }

    enum EntityKind: String, Identifiable {
        case author = "Author", series = "Series", publisher = "Publisher"
        var id: String { rawValue }
        var table: String {
            switch self { case .author: return "authors"; case .series: return "series"; case .publisher: return "publishers" }
        }
        var query: String {
            let idType = self == .publisher ? "bigint" : "Int"
            return """
            query CatalogEntities($ids: [\(idType)!]!) {
              entities: \(table)(where: {id: {_in: $ids}}) { id name }
            }
            """
        }
    }

    func search(_ query: String, kind: EntityKind, page: Int) async throws -> (entities: [CatalogEntity], hasMore: Bool) {
        let result: SearchResponse = try await request(Self.searchQuery, variables: ["query": query, "type": kind.rawValue, "page": page])
        guard let search = result.search else { throw CatalogError.invalidResponse }
        if let error = search.error, !error.isEmpty { throw CatalogError.message(error) }
        guard let ids = search.ids, !ids.isEmpty else { return ([], false) }
        let response: EntitiesResponse = try await request(kind.query, variables: ["ids": ids])
        let entities = Dictionary(response.entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (ids.compactMap { entities[$0] }, ids.count == 25)
    }

    func saveBook(original: CatalogBook, draft: CatalogBookDraft) async throws -> [String] {
        let patch = try draft.patch(from: original)
        guard !patch.isEmpty else { return [] }
        try await requireLibrarian()
        let latest = try await book(id: original.id)
        guard !latest.locked else { throw CatalogError.locked }
        guard latest == original else { throw CatalogError.conflict }
        if let coverID = draft.coverEditionID, coverID != original.defaultCoverEditionID {
            let coverEdition = try await edition(id: coverID)
            guard coverEdition.bookID == original.id, coverEdition.image != nil else {
                throw CatalogError.message(NSLocalizedString("Select a cover from an edition of this book.", comment: ""))
            }
        }
        return try await mutate(Self.updateBookMutation, id: original.id, input: patch)
    }

    func validateEditionSave(original: CatalogEdition, draft: CatalogEditionDraft) async throws {
        _ = try draft.patch(from: original)
        try await requireLibrarian()
        let latest = try await edition(id: original.id)
        guard !latest.locked else { throw CatalogError.locked }
        // Image imports only add to the gallery. They must not look like a metadata conflict on retry.
        guard sameEditionMetadata(latest, original) else { throw CatalogError.conflict }
    }

    func importCover(url: String, original: CatalogEdition) async throws -> Int {
        _ = try CatalogValidation.coverURL(url)
        try await requireLibrarian()
        let latest = try await edition(id: original.id)
        guard !latest.locked else { throw CatalogError.locked }
        guard sameEditionMetadata(latest, original) else { throw CatalogError.conflict }
        let response: MutationResponse = try await request(Self.importImageMutation, variables: [
            "image": ["imageable_id": original.id, "imageable_type": "Edition", "url": url]
        ], retryRateLimit: false)
        guard let id = response.result?.id, id > 0 else { throw CatalogError.invalidResponse }
        return id
    }

    func saveEdition(original: CatalogEdition, draft: CatalogEditionDraft) async throws -> [String] {
        let patch = try draft.patch(from: original)
        guard !patch.isEmpty else { return [] }
        try await validateEditionSave(original: original, draft: draft)
        return try await mutate(Self.updateEditionMutation, id: original.id, input: patch)
    }

    private func sameEditionMetadata(_ lhs: CatalogEdition, _ rhs: CatalogEdition) -> Bool {
        // Compare the fields that can be overwritten, not a gallery that may have grown independently.
        guard lhs.id == rhs.id, lhs.bookID == rhs.bookID, lhs.locked == rhs.locked else { return false }
        return (try? CatalogEditionDraft(lhs).patch(from: rhs).isEmpty) == true
    }

    private func mutate(_ query: String, id: Int, input: [String: Any]) async throws -> [String] {
        let response: MutationResponse = try await request(query, variables: ["id": id, "input": input], retryRateLimit: false)
        guard let result = response.result else { throw CatalogError.invalidResponse }
        let errors = (result.errors ?? []).filter { !$0.isEmpty }
        guard errors.isEmpty else { throw CatalogError.message(errors.joined(separator: "\n")) }
        guard result.id == id else { throw CatalogError.invalidResponse }
        return (result.warnings ?? []).filter { !$0.isEmpty }
    }

    static func retryDate(response: HTTPURLResponse, now: Date) -> Date {
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(header), seconds.isFinite, seconds >= 0 {
                return now.addingTimeInterval(max(1, seconds))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header), date > now { return date }
        }
        return now.addingTimeInterval(60)
    }

    private func checkAccount() throws {
        guard !authorization.isEmpty, authorization != "Bearer " else { throw CatalogError.permission }
        guard authorization == currentAuthorization() else { throw CatalogError.accountChanged }
        try Task.checkCancellation()
    }

    private func waitForRateLimit(allowWaiting: Bool) async throws {
        let waitLimit = now().addingTimeInterval(60)
        while let deadline = await requestGate.deadline(for: authorization, now: now()) {
            let delay = deadline.timeIntervalSince(now())
            guard allowWaiting, deadline <= waitLimit else { throw CatalogError.rateLimited(deadline) }
            try checkAccount()
            await onRateLimit(deadline)
            do { try await sleep(max(0, delay)) }
            catch {
                await onRateLimit(nil)
                throw error
            }
            await onRateLimit(nil)
            try checkAccount()
        }
    }

    private func request<T: Decodable>(_ query: String, variables: [String: Any] = [:], retryRateLimit: Bool = true) async throws -> T {
        try checkAccount()
        var request = URLRequest(url: URL(string: "https://api.hardcover.app/v1/graphql")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        // Only reads may be retried. A mutation is never replayed automatically.
        for attempt in 0...1 {
            try await waitForRateLimit(allowWaiting: retryRateLimit)
            try await beforeRequest(query)
            try checkAccount()
            let (data, response) = try await session.data(for: request)
            try checkAccount()
            guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
            await afterResponse(http)
            if http.statusCode == 429 {
                let date = Self.retryDate(response: http, now: now())
                await requestGate.deferRequests(for: authorization, until: date, now: now())
                guard retryRateLimit, attempt == 0, date.timeIntervalSince(now()) <= 60 else {
                    throw CatalogError.rateLimited(date)
                }
                continue
            }
            if http.statusCode == 401 {
                throw CatalogError.message(NSLocalizedString("Your Hardcover API key has expired or is invalid.", comment: ""))
            }
            if http.statusCode == 403 {
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let detail = body?["error_description"] as? String ?? ""
                throw CatalogError.message(NSLocalizedString("Hardcover denied access. The API key needs read:me:roles and write:catalog:edit, as well as catalog read and search access.", comment: "") + (detail.isEmpty ? "" : "\n\n" + detail))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw CatalogError.message(String(format: NSLocalizedString("Hardcover request failed (HTTP %d). Try again later.", comment: ""), http.statusCode))
            }
            let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
            if let errors = envelope.errors, !errors.isEmpty {
                throw CatalogError.message(errors.map(\.message).joined(separator: "\n"))
            }
            guard let result = envelope.data else { throw CatalogError.invalidResponse }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("mutation") { await afterMutation() }
            return result
        }
        throw CatalogError.invalidResponse
    }
}
