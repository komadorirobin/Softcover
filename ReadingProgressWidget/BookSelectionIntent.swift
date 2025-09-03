import WidgetKit
import AppIntents

struct BookSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Books"
    static var description = IntentDescription("Choose which books to display in the widget.")

    @Parameter(title: "Books", default: [])
    var books: [BookEntity]

    init() {
        self.books = []
    }
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
    
    private var cachedBooks: [BookEntity]?
    private var lastFetch: Date?
    private let cacheTimeout: TimeInterval = 60 // 1 minute cache
    
    func getBooks() async -> [BookEntity] {
        // Return cached books if they're still fresh
        if let cached = cachedBooks,
           let lastFetch = lastFetch,
           Date().timeIntervalSince(lastFetch) < cacheTimeout {
            return cached
        }
        
        // Fetch new books
        do {
            let books = await HardcoverService.fetchCurrentlyReading()
            let entities = books.map { BookEntity(id: $0.id, title: $0.title) }
            
            // Update cache
            self.cachedBooks = entities
            self.lastFetch = Date()
            
            return entities
        } catch {
            print("Error fetching books: \(error)")
            // Return cached books even if expired, or empty array
            return cachedBooks ?? []
        }
    }
    
    func clearCache() {
        cachedBooks = nil
        lastFetch = nil
    }
}

// The query that fetches the books.
struct BookQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BookEntity] {
        let allBooks = await BookCache.shared.getBooks()
        
        // If no books were fetched, try once more with a fresh fetch
        if allBooks.isEmpty {
            await BookCache.shared.clearCache()
            let retryBooks = await BookCache.shared.getBooks()
            return retryBooks.filter { identifiers.contains($0.id) }
        }
        
        return allBooks.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [BookEntity] {
        let books = await BookCache.shared.getBooks()
        
        // If no books were fetched, try once more with a fresh fetch
        if books.isEmpty {
            await BookCache.shared.clearCache()
            let retryBooks = await BookCache.shared.getBooks()
            
            // If still empty, throw a more descriptive error
            if retryBooks.isEmpty {
                throw BookQueryError.noBooksFound
            }
            
            return retryBooks
        }
        
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