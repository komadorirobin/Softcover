import Foundation
import Combine

struct ReadingAtlas: Codable, Equatable, Sendable {
    struct Genre: Codable, Equatable, Identifiable, Sendable {
        var id: String { name }
        let name: String
        let books: Int
    }

    struct Demographic: Codable, Equatable, Identifiable, Sendable {
        var id: String { label }
        let label: String
        let count: Int
    }

    let finishedBooks: Int
    let taggedBooks: Int
    let genres: [Genre]
    let distinctAuthors: Int
    let genders: [Demographic]
    let bipoc: [Demographic]
    let lgbtq: [Demographic]

    static let empty = ReadingAtlas(finishedBooks: 0, taggedBooks: 0, genres: [], distinctAuthors: 0,
                                    genders: [], bipoc: [], lgbtq: [])
}

enum ReadingAtlasAggregation {
    struct Author: Equatable, Sendable {
        let id: Int
        let genderID: Int?
        let isBIPOC: Bool?
        let isLGBTQ: Bool?
    }

    struct Book: Equatable, Sendable {
        let genres: [String]
        let authors: [Author]
    }

    static func make(books: [Book]) -> ReadingAtlas {
        let tagged = books.filter { !$0.genres.isEmpty }
        var genreCounts: [String: Int] = [:]
        for book in tagged {
            for genre in Set(book.genres.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }) {
                genreCounts[genre, default: 0] += 1
            }
        }
        var genres: [ReadingAtlas.Genre] = genreCounts.map { entry in
            ReadingAtlas.Genre(name: entry.key, books: entry.value)
        }
        genres.sort { left, right in
            if left.books != right.books { return left.books > right.books }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        let authors = Dictionary(books.flatMap(\.authors).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        func demographics(_ values: [(String, Int)]) -> [ReadingAtlas.Demographic] {
            values.filter { $0.1 > 0 }.map { .init(label: $0.0, count: $0.1) }
        }
        let genders = demographics([
            ("Women", authors.filter { $0.genderID == 2 }.count),
            ("Men", authors.filter { $0.genderID == 1 }.count),
            ("Other", authors.filter { $0.genderID == 3 }.count),
            ("Unknown", authors.filter { ![1, 2, 3].contains($0.genderID ?? -1) }.count)
        ])
        func booleanBreakdown(_ value: (Author) -> Bool?) -> [ReadingAtlas.Demographic] {
            demographics([
                ("Yes", authors.filter { value($0) == true }.count),
                ("No", authors.filter { value($0) == false }.count),
                ("Unknown", authors.filter { value($0) == nil }.count)
            ])
        }
        return ReadingAtlas(finishedBooks: books.count, taggedBooks: tagged.count, genres: genres,
                            distinctAuthors: authors.count, genders: genders,
                            bipoc: booleanBreakdown(\.isBIPOC), lgbtq: booleanBreakdown(\.isLGBTQ))
    }
}

enum ReadingAtlasService {
    static let query = """
    query SoftcoverReadingAtlas($userID: Int!, $limit: Int!, $offset: Int!) {
      user_books(
        where: {user_id: {_eq: $userID}, status_id: {_eq: 3}}
        order_by: [{last_read_date: desc_nulls_last}, {id: desc}]
        limit: $limit
        offset: $offset
      ) {
        book {
          taggable_counts(
            where: {tag: {tag_category: {category: {_eq: "Genre"}}}}
            order_by: {count: desc}
          ) { tag { tag } }
          contributions { author { id gender_id is_bipoc is_lgbtq } }
        }
      }
    }
    """

    static func fetch() async throws -> ReadingAtlas {
        let user = try await LibraryAPI.identity()
        var offset = 0
        var books: [ReadingAtlasAggregation.Book] = []
        while offset < 10_000 {
            let data = try await LibraryAPI.request(query, variables: ["userID": user.id, "limit": 100, "offset": offset])
            let page = try decode(data)
            books.append(contentsOf: page)
            guard page.count == 100 else { break }
            offset += page.count
        }
        return ReadingAtlasAggregation.make(books: books)
    }

    static func decode(_ data: Data) throws -> [ReadingAtlasAggregation.Book] {
        struct Response: Decodable {
            struct Payload: Decodable { let user_books: [Row] }
            struct Row: Decodable { let book: Book? }
            struct Book: Decodable {
                struct Count: Decodable { struct Tag: Decodable { let tag: String }; let tag: Tag? }
                struct Contribution: Decodable { let author: Author? }
                struct Author: Decodable {
                    let id: Int
                    let gender_id: Int?
                    let is_bipoc: Bool?
                    let is_lgbtq: Bool?
                }
                let taggable_counts: [Count]?
                let contributions: [Contribution]?
            }
            let data: Payload
        }
        let rows = try JSONDecoder().decode(Response.self, from: data).data.user_books
        return rows.compactMap { row in
            guard let book = row.book else { return nil }
            return ReadingAtlasAggregation.Book(
                genres: book.taggable_counts?.compactMap { $0.tag?.tag } ?? [],
                authors: book.contributions?.compactMap { value in
                    value.author.map { .init(id: $0.id, genderID: $0.gender_id,
                                             isBIPOC: $0.is_bipoc, isLGBTQ: $0.is_lgbtq) }
                } ?? []
            )
        }
    }
}

@MainActor
final class ReadingAtlasStore: ObservableObject {
    @Published private(set) var atlas: ReadingAtlas?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var account = ""

    func load(refresh: Bool = false) async {
        let current = HardcoverConfig.accountIdentifier
        if account != current {
            account = current
            atlas = Self.cached(account: current)
        }
        guard refresh || atlas == nil else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let value = try await ReadingAtlasService.fetch()
            guard current == HardcoverConfig.accountIdentifier else { return }
            atlas = value
            Self.cache(value, account: current)
        } catch {
            guard current == HardcoverConfig.accountIdentifier else { return }
            self.error = error.localizedDescription
        }
    }

    private static func key(_ account: String) -> String {
        "ReadingAtlas.\(HardcoverRequestScheduler.accountKey(account))"
    }
    private static func cached(account: String) -> ReadingAtlas? {
        AppGroup.defaults.data(forKey: key(account)).flatMap { try? JSONDecoder().decode(ReadingAtlas.self, from: $0) }
    }
    private static func cache(_ atlas: ReadingAtlas, account: String) {
        if let data = try? JSONEncoder().encode(atlas) { AppGroup.defaults.set(data, forKey: key(account)) }
    }
}
