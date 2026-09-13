import WidgetKit
import AppIntents

struct BookSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Widget"
    static var description = IntentDescription("Choose how books are displayed in the widget.")

    @Parameter(title: "Display Mode", default: .recentlyUpdated)
    var displayMode: DisplayMode
    
    @Parameter(title: "Books")
    var books: [BookEntity]?

    init() {
        self.displayMode = .recentlyUpdated
        self.books = nil
    }
}

enum DisplayMode: String, AppEnum {
    case recentlyUpdated = "Recently Updated"
    case manualSelection = "Manual Selection"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Display Mode"
    
    static var caseDisplayRepresentations: [DisplayMode: DisplayRepresentation] = [
        .recentlyUpdated: "Recently Updated",
        .manualSelection: "Manual Selection"
    ]
}

// Represents a single book that the user can select.
struct BookEntity: AppEntity {
    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Book"
    static var defaultQuery = BookQuery()
}

// Cache for books to avoid repeated API calls
actor BookCache {
    static let shared = BookCache()

    private var cachedBooks: [BookEntity] = []
    private var lastFetch = Date.distantPast
    private var token: WidgetSnapshotStore.Token?

    func getBooks() async -> [BookEntity] {
        guard !HardcoverConfig.apiKey.isEmpty else { clearCache(); return [] }
        let expected = WidgetSnapshotStore.token(kind: WidgetSync.readingKind)
        if token == expected, Date().timeIntervalSince(lastFetch) < 60 {
            return cachedBooks
        }
        do {
            let books: [BookProgress]
            if let snapshot = LibrarySnapshot.load(status: 2, maxAge: 300), !snapshot.stale, snapshot.complete {
                books = snapshot.books
            } else {
                books = try await LibraryAPI.page(status: 2, limit: 100).books
            }
            guard expected == WidgetSnapshotStore.token(kind: expected.kind) else { return [] }
            let entities = books.map { BookEntity(id: $0.id, title: $0.title) }
            self.cachedBooks = entities
            self.lastFetch = Date()
            self.token = expected
            return entities
        } catch {
            guard token?.account == expected.account, Date().timeIntervalSince(lastFetch) < 3600 else { return [] }
            return cachedBooks
        }
    }
    
    func clearCache() {
        cachedBooks = []
        lastFetch = .distantPast
        token = nil
    }
}

// The query that fetches the books.
struct BookQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BookEntity] {
        try await WidgetReaders.selectedBooks(ids: identifiers).map { BookEntity(id: $0.id, title: $0.title) }
    }
    
    func suggestedEntities() async throws -> [BookEntity] {
        let books = await BookCache.shared.getBooks()
        
        return books
    }
    
    func defaultResult() async -> BookEntity? {
        let books = await BookCache.shared.getBooks()
        return books.first
    }
}

enum BookQueryError: LocalizedError {
    case noBooksFound
    
    var errorDescription: String? {
        switch self {
        case .noBooksFound:
            return "No books found. Please make sure you have books in your Currently Reading list on Hardcover."
        }
    }
}
