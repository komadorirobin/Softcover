import SwiftUI

struct UserSearchResult: Identifiable, Decodable, Hashable {
    let id: Int
    let username: String
    let name: String?
    let image: String?
    let bio: String?

    init(id: Int, username: String, name: String?, image: String?, bio: String?) {
        self.id = id; self.username = username; self.name = name; self.image = image; self.bio = bio
    }
    private enum CodingKeys: String, CodingKey { case id, username, name, image, bio }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? values.decode(Int.self, forKey: .id) { id = value }
        else { id = Int(try values.decode(String.self, forKey: .id)) ?? 0 }
        guard id > 0 else { throw HardcoverNetworkError.invalidResponse }
        username = try values.decode(String.self, forKey: .username)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        bio = try values.decodeIfPresent(String.self, forKey: .bio)
        if let object = try? values.decode(BookImage.self, forKey: .image) { image = object.url }
        else { image = try? values.decode(String.self, forKey: .image) }
    }
}

enum BookSearchAPI {
    static let query = """
    query SoftcoverSearch($query: String!, $type: String!, $page: Int!) {
      search(query: $query, query_type: $type, page: $page, per_page: 25) { ids results error }
    }
    """
    static let hydrateQuery = """
    query SoftcoverSearchBooks($ids: [Int!]!) {
      books(where: {id: {_in: $ids}}) { id title cached_contributors image { url } }
    }
    """
    static let usersQuery = """
    query SoftcoverSearchUsers($ids: [Int!]!) {
      users(where: {id: {_in: $ids}}) { id username name bio image { url } }
    }
    """
    static let statusQuery = """
    query SoftcoverSearchStatus($userID: Int!, $ids: [Int!]!) {
      user_books(where: {user_id: {_eq: $userID}, book_id: {_in: $ids}}) {
        book_id status_id user_book_reads(order_by: {id: desc}, limit: 1) { finished_at }
      }
    }
    """

    struct Page { let books: [BookProgress]; let users: [UserSearchResult]; let hasMore: Bool }

    static func search(text: String, type: String, page: Int) async throws -> Page {
        let data = try await LibraryAPI.request(query, variables: ["query": normalized(text), "type": type, "page": page])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = (root["data"] as? [String: Any])?["search"] as? [String: Any] else { throw HardcoverNetworkError.invalidResponse }
        if let error = value["error"] as? String, !error.isEmpty { throw HardcoverNetworkError.graphQL(error) }
        let ids = (value["ids"] as? [Any])?.compactMap { ($0 as? Int) ?? ($0 as? String).flatMap(Int.init) }
        let rawResults = value["results"] as? [[String: Any]]
        guard ids != nil || rawResults != nil else { throw HardcoverNetworkError.invalidResponse }
        let hasMore = (ids?.count ?? rawResults?.count ?? 0) == 25
        if type == "Book" {
            var books: [HydratedBook] = []
            if let rawResults {
                books = try JSONDecoder().decode([SearchBookResult].self, from: JSONSerialization.data(withJSONObject: rawResults)).map(\.hydratedBook)
            }
            if books.isEmpty, let ids, !ids.isEmpty {
                let data = try await LibraryAPI.request(hydrateQuery, variables: ["ids": ids])
                guard let loaded = try JSONDecoder().decode(GraphQLBooksHydrateResponse.self, from: data).data?.books else { throw HardcoverNetworkError.invalidResponse }
                let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                books = ids.compactMap { byID[$0] }
            }
            return Page(books: books.map { $0.progressModel }, users: [], hasMore: hasMore)
        }
        var users: [UserSearchResult] = []
        if let rawResults {
            users = try JSONDecoder().decode([UserSearchResult].self, from: JSONSerialization.data(withJSONObject: rawResults))
        }
        if users.isEmpty, let ids, !ids.isEmpty {
            struct Response: Decodable { struct Value: Decodable { let users: [UserSearchResult] }; let data: Value }
            let data = try await LibraryAPI.request(usersQuery, variables: ["ids": ids])
            let loaded = try JSONDecoder().decode(Response.self, from: data).data.users
            let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            users = ids.compactMap { byID[$0] }
        }
        return Page(books: [], users: users, hasMore: hasMore)
    }

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "author:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func statuses(for books: [BookProgress]) async throws -> [Int: Int] {
        let ids = books.compactMap(\.bookId)
        guard !ids.isEmpty else { return [:] }
        let user = try await LibraryAPI.identity()
        let data = try await LibraryAPI.request(statusQuery, variables: ["userID": user.id, "ids": ids])
        struct Response: Decodable {
            struct Value: Decodable { let user_books: [Row] }
            struct Row: Decodable { let book_id: Int; let status_id: Int }
            let data: Value
        }
        return Dictionary(try JSONDecoder().decode(Response.self, from: data).data.user_books.map { ($0.book_id, $0.status_id) }, uniquingKeysWith: { _, last in last })
    }
}

extension HydratedBook {
    var progressModel: BookProgress {
        BookProgress(id: "book-\(id)", title: title, author: contributions?.compactMap { $0.author?.name }.joined(separator: ", ") ?? "",
                     coverImageUrl: image?.url, bookId: id, originalTitle: title)
    }
}

@MainActor
final class BookSearchStore: ObservableObject {
    struct Request: Hashable { let text: String; let type: String; let account: String }
    @Published private(set) var books: [BookProgress] = []
    @Published private(set) var users: [UserSearchResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var error: String?
    @Published private(set) var completed = false
    @Published private(set) var statuses: [Int: Int] = [:]
    private var request: Request?
    private var generation = UUID()
    private var page = 1

    func search(_ input: Request, debounce: Bool = true) async {
        let token = UUID()
        generation = token
        request = input
        books = []; users = []; statuses = [:]; error = nil; completed = false; hasMore = false; page = 1; isLoadingMore = false
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { isLoading = false; return }
        isLoading = true
        defer { if generation == token { isLoading = false } }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(350)) }
            let result = try await BookSearchAPI.search(text: input.text, type: input.type, page: 1)
            try Task.checkCancellation()
            guard matches(input, token: token) else { return }
            books = result.books; users = result.users; hasMore = result.hasMore; completed = true
            isLoading = false
            await loadStatuses(result.books, input: input, token: token)
        } catch is CancellationError { }
        catch { if matches(input, token: token) { self.error = error.localizedDescription } }
    }

    func loadMore() async {
        guard let input = request, !isLoading, !isLoadingMore, hasMore else { return }
        let token = generation
        isLoadingMore = true
        error = nil
        defer { if generation == token { isLoadingMore = false } }
        do {
            let result = try await BookSearchAPI.search(text: input.text, type: input.type, page: page + 1)
            try Task.checkCancellation()
            guard matches(input, token: token) else { return }
            let bookIDs = Set(books.map(\.id)), userIDs = Set(users.map(\.id))
            books += result.books.filter { !bookIDs.contains($0.id) }
            users += result.users.filter { !userIDs.contains($0.id) }
            hasMore = result.hasMore; page += 1
            await loadStatuses(result.books, input: input, token: token)
        } catch is CancellationError { }
        catch { if matches(input, token: token) { self.error = error.localizedDescription } }
    }

    func markAdded(_ bookID: Int) { statuses[bookID] = 1 }
    func setStatus(bookID: Int, status: Int) { statuses[bookID] = status }

    private func matches(_ input: Request, token: UUID) -> Bool {
        generation == token && request == input && input.account == HardcoverConfig.authorizationHeaderValue
    }
    private func loadStatuses(_ books: [BookProgress], input: Request, token: UUID) async {
        guard let result = try? await BookSearchAPI.statuses(for: books), !Task.isCancelled, matches(input, token: token) else { return }
        statuses.merge(result, uniquingKeysWith: { _, last in last })
    }
}
