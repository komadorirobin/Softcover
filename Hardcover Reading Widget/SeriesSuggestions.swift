import SwiftUI

struct SeriesSuggestionCandidate: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(seriesID)-\(book.bookId ?? 0)" }
    let seriesID: Int
    let seriesName: String
    let position: Double
    let book: BookProgress
}

enum SeriesSuggestionService {
    static let seedsQuery = """
    query SoftcoverSeriesSeeds {
      me {
        user_books(
          where: {status_id: {_in: [2, 3]}}
          order_by: {id: desc}
          limit: 1000
        ) {
          book_id
          book { book_series { series_id position series { name } } }
        }
      }
    }
    """
    static let candidatesQuery = """
    query SoftcoverNextInSeries($where: book_series_bool_exp!) {
      book_series(where: $where, order_by: [{position: asc}, {book: {users_count: desc}}], limit: 5000) {
        series_id position
        series { name }
        book {
          id title rating release_date cached_contributors image { url }
        }
      }
    }
    """

    static func fetch() async throws -> [SeriesSuggestionCandidate] {
        let seedData = try await LibraryAPI.request(seedsQuery)
        let seeds = try decodeSeeds(seedData)
        guard !seeds.positions.isEmpty else { return [] }
        let clauses = seeds.positions.keys.sorted().compactMap { seriesID -> [String: Any]? in
            guard let position = seeds.positions[seriesID] else { return nil }
            return ["series_id": ["_eq": seriesID], "position": ["_gt": position]]
        }
        // Hardcover bills this document as one request: it has one top-level field,
        // regardless of how many clauses are inside the `where` expression.
        let data = try await LibraryAPI.request(candidatesQuery, variables: ["where": ["_or": clauses]], cost: 1)
        return try decodeCandidates(data).filter { candidate in
            candidate.book.bookId.map { !seeds.ownedBookIDs.contains($0) } ?? false
        }
    }

    static func decodeSeeds(_ data: Data) throws -> (positions: [Int: Double], ownedBookIDs: Set<Int>) {
        struct Response: Decodable {
            struct Payload: Decodable {
                struct CurrentUser: Decodable { let user_books: [Row] }
                let me: [CurrentUser]
            }
            struct Row: Decodable {
                struct Book: Decodable {
                    struct Series: Decodable { struct Name: Decodable { let name: String? }; let series_id: Int?; let position: Double?; let series: Name? }
                    let book_series: [Series]?
                }
                let book_id: Int?
                let book: Book?
            }
            let data: Payload
        }
        guard let rows = try JSONDecoder().decode(Response.self, from: data).data.me.first?.user_books else {
            throw HardcoverNetworkError.invalidResponse
        }
        var positions: [Int: Double] = [:]
        var ids = Set<Int>()
        for row in rows {
            if let id = row.book_id { ids.insert(id) }
            for series in row.book?.book_series ?? [] {
                guard let id = series.series_id, let position = series.position else { continue }
                positions[id] = max(positions[id] ?? -Double.infinity, position)
            }
        }
        return (positions, ids)
    }

    static func decodeCandidates(_ data: Data) throws -> [SeriesSuggestionCandidate] {
        struct Response: Decodable {
            struct Payload: Decodable { let book_series: [Row] }
            struct Row: Decodable {
                struct Series: Decodable { let name: String? }
                struct Book: Decodable {
                    struct Image: Decodable { let url: String? }
                    struct Contribution: Decodable { struct Author: Decodable { let name: String? }; let author: Author? }
                    let id: Int
                    let title: String
                    let rating: Double?
                    let release_date: String?
                    let cached_contributors: [Contribution]?
                    let image: Image?
                }
                let series_id: Int
                let position: Double
                let series: Series?
                let book: Book
            }
            let data: Payload
        }
        return try JSONDecoder().decode(Response.self, from: data).data.book_series.map { row in
            let author = row.book.cached_contributors?.compactMap { $0.author?.name }.joined(separator: ", ") ?? ""
            let book = BookProgress(id: "series-\(row.book.id)", title: row.book.title.decodedHTMLEntities,
                author: author, coverImageUrl: row.book.image?.url, bookId: row.book.id,
                originalTitle: row.book.title.decodedHTMLEntities, editionAverageRating: row.book.rating,
                releaseDate: row.book.release_date, parsedReleaseDate: ReleaseDate.parse(row.book.release_date))
            return SeriesSuggestionCandidate(seriesID: row.series_id,
                seriesName: row.series?.name?.isEmpty == false ? row.series!.name! : "Series",
                position: row.position, book: book)
        }
    }
}

@MainActor
final class HiddenSuggestionsStore: ObservableObject {
    struct Item: Codable, Hashable, Identifiable {
        enum Kind: String, Codable { case book, series }
        var id: String { "\(kind.rawValue)-\(value)" }
        let kind: Kind
        let value: Int
        let title: String
    }

    static let shared = HiddenSuggestionsStore()
    @Published private(set) var items: [Item] = []
    private var account = ""
    private init() { reload() }

    func reload() {
        let current = HardcoverConfig.accountIdentifier
        guard account != current else { return }
        account = current
        items = AppGroup.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }
    func hides(bookID: Int) -> Bool { items.contains { $0.kind == .book && $0.value == bookID } }
    func hides(seriesID: Int) -> Bool { items.contains { $0.kind == .series && $0.value == seriesID } }
    func hideBook(_ book: BookProgress) {
        guard let id = book.bookId else { return }
        add(.init(kind: .book, value: id, title: book.title))
    }
    func hideSeries(id: Int, title: String) { add(.init(kind: .series, value: id, title: title)) }
    func restore(_ item: Item) { items.removeAll { $0.id == item.id }; persist() }
    func restoreAll() { items = []; persist() }
    private func add(_ item: Item) { items.removeAll { $0.id == item.id }; items.append(item); persist() }
    private var key: String { "HiddenSuggestions.\(HardcoverRequestScheduler.accountKey(account))" }
    private func persist() { if let data = try? JSONEncoder().encode(items) { AppGroup.defaults.set(data, forKey: key) } }
}

@MainActor
final class SeriesSuggestionsStore: ObservableObject {
    @Published private(set) var candidates: [SeriesSuggestionCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var account = ""

    func load(refresh: Bool = false) async {
        let current = HardcoverConfig.accountIdentifier
        if account != current { account = current; candidates = cached() }
        guard refresh || candidates.isEmpty else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let value = try await SeriesSuggestionService.fetch()
            guard current == HardcoverConfig.accountIdentifier else { return }
            candidates = value
            if let data = try? JSONEncoder().encode(value) { AppGroup.defaults.set(data, forKey: key) }
        } catch { if current == HardcoverConfig.accountIdentifier { self.error = error.localizedDescription } }
    }
    private var key: String { "SeriesSuggestions.\(HardcoverRequestScheduler.accountKey(account))" }
    private func cached() -> [SeriesSuggestionCandidate] {
        AppGroup.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([SeriesSuggestionCandidate].self, from: $0) } ?? []
    }
}

struct SeriesSuggestionsView: View {
    @StateObject private var store = SeriesSuggestionsStore()
    @ObservedObject private var hidden = HiddenSuggestionsStore.shared
    @State private var selectedBook: BookProgress?

    private var suggestions: [SeriesSuggestionCandidate] {
        let visible = store.candidates.filter { candidate in
            !hidden.hides(seriesID: candidate.seriesID) && !(candidate.book.bookId.map(hidden.hides(bookID:)) ?? false)
        }
        return Dictionary(grouping: visible, by: \.seriesID).values.compactMap { $0.min { $0.position < $1.position } }
            .sorted { $0.seriesName.localizedCaseInsensitiveCompare($1.seriesName) == .orderedAscending }
    }

    var body: some View {
        List {
            if let error = store.error { InlineLoadError(message: error) { Task { await store.load(refresh: true) } } }
            if store.isLoading && store.candidates.isEmpty { ProgressView("Finding your next books…").frame(maxWidth: .infinity) }
            ForEach(suggestions) { suggestion in
                BookRow(book: suggestion.book, subtitle: "Up next in \(suggestion.seriesName)") {
                    selectedBook = suggestion.book
                }
                .contextMenu {
                    Button("Hide this book", systemImage: "eye.slash") { hidden.hideBook(suggestion.book) }
                    Button("Hide this series", systemImage: "rectangle.stack.badge.minus") {
                        hidden.hideSeries(id: suggestion.seriesID, title: suggestion.seriesName)
                    }
                }
            }
            if !store.isLoading && suggestions.isEmpty && store.error == nil {
                ContentUnavailableView("No series suggestions", systemImage: "books.vertical",
                    description: Text("Finish or start a book in a series and Softcover will find what comes next."))
            }
        }
        .listStyle(.plain).refreshable { await store.load(refresh: true) }.task { hidden.reload(); await store.load() }
        .navigationDestination(item: $selectedBook) { BookDetailView(book: $0) }
    }
}

struct HiddenSuggestionsView: View {
    @ObservedObject private var hidden = HiddenSuggestionsStore.shared
    var body: some View {
        List {
            ForEach(hidden.items) { item in
                HStack {
                    Label(item.title, systemImage: item.kind == .series ? "rectangle.stack" : "book.closed")
                    Spacer()
                    Button("Restore") { hidden.restore(item) }.buttonStyle(.bordered)
                }
            }
            if hidden.items.isEmpty {
                ContentUnavailableView("Nothing hidden", systemImage: "eye", description: Text("Hidden books and series will appear here."))
            }
        }
        .navigationTitle("Hidden Suggestions")
        .toolbar { if !hidden.items.isEmpty { Button("Restore All") { hidden.restoreAll() } } }
        .task { hidden.reload() }
    }
}
