#if BOOK_UI_FIXTURE
import SwiftUI

// This target never uses the app group or production transport. Every operation is in memory.
enum AppGroup { static let defaults = UserDefaults.standard }
enum HardcoverConfig {
    static var apiKey: String { "book-ui-fixture" }
    static var authorizationHeaderValue: String { "Bearer book-ui-fixture" }
}
enum HardcoverNetworkError: LocalizedError {
    case invalidResponse, accountChanged
    var errorDescription: String? { "Fixture response unavailable." }
}
extension String { var decodedHTMLEntities: String { self } }
enum ReleaseDate {
    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateFormatter().date(from: string + "T12:00:00Z")
    }
}
struct LibraryPage { let books: [BookProgress]; let hasMore: Bool; let nextOffset: Int }
enum LibrarySnapshot {
    struct Value { let books: [BookProgress]; let complete: Bool; var stale = false }
    static func load(status: Int) -> Value? { nil }
    static func save(_ books: [BookProgress], status: Int, complete: Bool) { }
    static func update(book: BookProgress) { }
    static func invalidate(status: Int) { }
}
extension Notification.Name { static let libraryDidChange = Notification.Name("BookListsNeedRefresh") }
enum WidgetSync {
    static func progressChanged(book: BookProgress) { }
    static func libraryChanged(statuses: [Int]) { }
}
@MainActor enum FixtureData {
    static var books: [BookProgress] = [
        BookProgress(id: "101", title: "The Fragrant Flower Blooms With Dignity, Vol. 5", author: "Saka Mikami",
            coverImageData: cover("FRAGRANT\nFLOWER", color: .systemPink), progress: 0.37, totalPages: 216, currentPage: 80,
            bookId: 1, userBookId: 101, editionId: 201, originalTitle: "The Fragrant Flower Blooms With Dignity, Vol. 5",
            editionAverageRating: 4.3, readingFormat: "Ebook", statusId: 2),
        BookProgress(id: "102", title: "The Left Hand of Darkness", author: "Ursula K. Le Guin",
            coverImageData: cover("THE LEFT\nHAND OF\nDARKNESS", color: .systemTeal), progress: 0.3, totalPages: 216, currentPage: 0,
            bookId: 2, userBookId: 102, editionId: 202, originalTitle: "The Left Hand of Darkness", editionAverageRating: 4.1,
            isAudiobook: true, totalMinutes: 600, currentMinute: 180, readingFormat: "Audio", statusId: 2),
        BookProgress(id: "103", title: "En riktigt lång svensk boktitel som ska kunna läsas även med större text", author: "Författare med ett långt namn",
            coverImageData: cover("EN LÅNG\nBOKTITEL", color: .systemIndigo), progress: 0.2, totalPages: 360, currentPage: 72,
            bookId: 3, userBookId: 103, editionId: 203, originalTitle: "En riktigt lång svensk boktitel som ska kunna läsas även med större text",
            readingFormat: "Physical", statusId: 2)
    ]
    static func cover(_ text: String, color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 180, height: 270)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 180, height: 270))
            let style = NSMutableParagraphStyle(); style.alignment = .center
            (text as NSString).draw(in: CGRect(x: 12, y: 75, width: 156, height: 170), withAttributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: style
            ])
        }.pngData()!
    }
}
@MainActor enum LibraryAPI {
    static var metadataRequests = 0
    static var ownRequests = 0
    static var raceMetadata = false
    static var racePersonal = false
    struct User { let id: Int }
    static func identity() async throws -> User { User(id: 1) }
    static func ownBook(bookID: Int, fresh: Bool = false) async throws -> BookProgress? {
        if CommandLine.arguments.contains("social") { return nil }
        if racePersonal {
            ownRequests += 1
            let first = ownRequests == 1
            try await Task.sleep(for: .milliseconds(first ? 150 : 10))
            return FixtureData.books[0].withProgress(first ? 20 : 100)
        }
        return FixtureData.books.first { $0.bookId == bookID }
    }
    static func page(status: Int, offset: Int = 0, username: String? = nil, fresh: Bool = false) async throws -> LibraryPage {
        if CommandLine.arguments.contains("offline") { throw HardcoverNetworkError.invalidResponse }
        return LibraryPage(books: FixtureData.books, hasMore: false, nextOffset: 3)
    }
    static func request(_ query: String, variables: [String: Any] = [:], fresh: Bool = false, cost: Int = 1) async throws -> Data {
        if CommandLine.arguments.contains("offline") { throw HardcoverNetworkError.invalidResponse }
        let value: [String: Any]
        if query.contains("BookDetails") {
            if raceMetadata {
                metadataRequests += 1
                let first = metadataRequests == 1
                try await Task.sleep(for: .milliseconds(first ? 150 : 10))
                return try JSONSerialization.data(withJSONObject: ["data": ["books": [["title": "Fixture", "description": first ? "older" : "newer"]]]])
            }
            value = ["books": [["title": FixtureData.books[0].title, "description": "An unlikely friendship grows between students from two neighboring schools. Their story unfolds through quiet moments, shared meals, and the courage to be honest with one another.", "rating": 4.3,
                "cached_contributors": [["author": ["name": "Saka Mikami"]]], "cached_tags": ["genres": ["Manga", "Romance"], "moods": ["Hopeful"]]]]]
        } else if query.contains("BookQuotes") {
            value = ["user_books": [["book": ["title": FixtureData.books[0].title], "reading_journals": [["id": 1, "entry": "A small act of kindness can change the way we see the world."]]]]]
        } else if query.contains("BookReviewLikes") {
            value = ["likes": [], "mine": []]
        } else {
            value = ["user_books": [["id": 300, "rating": 4.5, "review_raw": "Beautifully drawn, with characters worth spending time with.", "user": ["username": "reader"]]]]
        }
        return try JSONSerialization.data(withJSONObject: ["data": value])
    }
}
struct Edition: Identifiable { let id: Int; let title: String? }
@MainActor enum HardcoverService {
    struct PublicReview: Identifiable {
        let id: Int; let rating: Double?; let reviewedAt: Date?; let text: String?; let username: String?
        let likesCount: Int; let userHasLiked: Bool
    }
    struct TrendingBook: Identifiable { let id: Int; let title: String; let author: String; let coverImageUrl: String? }
    static func updateProgress(userBookId: Int, editionId: Int?, page: Int, isAudiobook: Bool) async -> Bool {
        guard let index = FixtureData.books.firstIndex(where: { $0.userBookId == userBookId }) else { return false }
        FixtureData.books[index] = FixtureData.books[index].withProgress(page)
        return !CommandLine.arguments.contains("save-error")
    }
    static func fetchEditions(for id: Int) async -> [Edition] { [Edition(id: 201, title: "E-book"), Edition(id: 202, title: "Paperback")] }
    static func updateEdition(userBookId: Int, editionId: Int) async -> Bool { true }
    static func updateUserBookStatus(userBookId: Int, statusId: Int) async -> Bool { true }
    static func deleteUserBook(userBookId: Int) async -> Bool { true }
    static func addBookToWantToRead(bookId: Int, editionId: Int?) async -> Bool { true }
    static func startReadingBook(bookId: Int, editionId: Int?) async -> Bool { true }
    static func publishReview(userBookId: Int, text: String, hasSpoilers: Bool) async -> Bool { !CommandLine.arguments.contains("save-error") }
    static func updateUserBookRating(userBookId: Int, rating: Double?) async -> Bool { true }
    static func finishBook(userBookId: Int, editionId: Int?, totalPages: Int?, currentPage: Int?, rating: Double?) async -> Bool { true }
}
extension View {
    func catalogEditing(book: Binding<BookProgress>, onUpdated: @escaping (BookProgress) -> Void) -> some View {
        toolbar { ToolbarItem(placement: .primaryAction) { Button {} label: { Image(systemName: "pencil").frame(width: 44, height: 44) }.accessibilityLabel("Edit on Hardcover") } }
    }
}
struct WrapChipsView: View {
    let items: [String]
    var body: some View { Text(items.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
}
struct SearchReviewRow: View {
    let review: HardcoverService.PublicReview
    var body: some View { VStack(alignment: .leading) { Text("@\(review.username ?? "")").font(.caption); Text(review.text ?? "").font(.subheadline) } }
}
struct EditionRow: View {
    let edition: Edition; let isSelected: Bool; let isCurrent: Bool; let onTap: () -> Void
    var body: some View { Button(action: onTap) { Label(edition.title ?? "", systemImage: isSelected ? "checkmark.circle.fill" : "circle").frame(minHeight: 44) } }
}
struct EditionSelectionSheet: View {
    let bookTitle: String; let currentEditionId: Int?; let editions: [Edition]; let onCancel: () -> Void; let onSave: (Int?) -> Void
    var body: some View { Text(bookTitle) }
}
struct ReadingDatesView: View { let userBookId: Int; let editionId: Int?; var body: some View { Text("Dates Read") } }
struct BookQuotesView: View {
    let bookId: Int; let bookTitle: String; let editionId: Int?; let totalPages: Int?; let highlightQuoteId: Int?
    var body: some View { Text("Quotes") }
}
struct WantToReadView: View { let onComplete: (Bool) -> Void; var body: some View { Text("Want to Read") } }
struct ExplorerView: View { let onComplete: (Bool) -> Void; var body: some View { Text("Explore") } }
struct SearchBooksView: View { let onDone: (Bool) -> Void; var body: some View { Text("Search Books") } }
struct ProfileView: View { var body: some View { Text("Profile") } }
struct StatsView: View { var highlightGoalID: Int? = nil; var body: some View { Text("Reading goals") } }
struct ApiKeySettingsView: View { let onSaved: (String) -> Void; var body: some View { Text("Settings") } }

@main struct BookUIFixture: App {
    init() {
        UserDefaults.standard.set("book-ui-fixture", forKey: "HardcoverAPIKey")
        // Fail closed: URL loading is disabled, even if a future view introduces a request.
        URLProtocol.registerClass(NoNetworkProtocol.self)
        var audio = ReadingProgressDraft(book: FixtureData.books[1])
        audio.units = 400
        precondition(audio.isValid && audio.total == 600, "Audiobook units must not use page count")
        audio.percent = 50
        precondition(audio.units == 300)
        audio.units = 601
        precondition(!audio.isValid)
    }
    var body: some Scene {
        WindowGroup {
            FixtureRoot()
                .environment(\.dynamicTypeSize, CommandLine.arguments.contains("large-text") ? .accessibility3 : .large)
                .preferredColorScheme(CommandLine.arguments.contains("dark") ? .dark : .light)
                .task {
                    if CommandLine.arguments.contains("checks") {
                        await runStoreChecks()
                        print("Book UI checks passed: typed audio/percent bounds; metadata/own-book reversed response ordering; empty tag decoding")
                        exit(0)
                    }
                }
        }
    }

    @MainActor private func runStoreChecks() async {
        LibraryAPI.raceMetadata = true
        let metadataStore = BookDetailStore(bookID: 1)
        let older = Task { await metadataStore.load() }
        try? await Task.sleep(for: .milliseconds(20))
        await metadataStore.load(fresh: true)
        await older.value
        precondition(metadataStore.metadata?.description == "newer")
        precondition(metadataStore.metadata?.genres == [] && metadataStore.metadata?.moods == [])
        LibraryAPI.raceMetadata = false
        LibraryAPI.racePersonal = true
        let personalStore = BookDetailStore(bookID: 1)
        let oldPersonal = Task { await personalStore.refreshOwnBook() }
        try? await Task.sleep(for: .milliseconds(20))
        await personalStore.refreshOwnBook()
        await oldPersonal.value
        precondition(personalStore.ownBook?.currentUnits == 100)
        LibraryAPI.racePersonal = false
    }
}
private struct FixtureRoot: View {
    var body: some View {
        if CommandLine.arguments.contains("progress") {
            ReadingProgressEditor(book: FixtureData.books[CommandLine.arguments.contains("audio") ? 1 : 0]) { _ in }
        } else if CommandLine.arguments.contains("finish") {
            FinishRateReviewSheet(book: FixtureData.books[0], markFinished: true) { _ in }
        } else if CommandLine.arguments.contains("detail") || CommandLine.arguments.contains("social") {
            NavigationStack {
                BookDetailView(book: FixtureData.books[0], isOwnBook: !CommandLine.arguments.contains("social"))
            }
        } else { ContentView() }
    }
}
private final class NoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() { }
}
#endif
