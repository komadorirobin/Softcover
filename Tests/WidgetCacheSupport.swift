import Foundation
import CryptoKit

// No credentials, live network, WidgetCenter, or UIKit are used in these checks.
enum AppGroup {
    static let suite = "Softcover.WidgetCacheChecks.\(ProcessInfo.processInfo.processIdentifier)"
    static var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
}
enum HardcoverConfig {
    static var apiKey: String {
        get { AppGroup.defaults.string(forKey: "testAccount") ?? "" }
        set { AppGroup.defaults.set(newValue, forKey: "testAccount") }
    }
    static var authorizationHeaderValue: String { apiKey }
}
enum HardcoverRequestScheduler {
    static func accountKey(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
struct WidgetCenter: Sendable {
    static let shared = Self()
    func reloadTimelines(ofKind: String) {}
}
struct ReadingGoal: Codable, Sendable { let id: Int }
enum HardcoverService {
    struct UpcomingRelease: Sendable {
        let id: Int
        let bookId: Int?
        let title: String
        let author: String
        let releaseDate: Date
        let coverImageData: Data?
    }
    struct ReadingJournalQuote: Codable, Sendable {
        let id: Int
        let entry: String
        let bookId: Int
        let createdAt: String
        let book: QuoteBook
        enum CodingKeys: String, CodingKey { case id, entry, bookId = "book_id", createdAt = "created_at", book }
        struct QuoteBook: Codable, Sendable {
            let title: String
            let contributions: [Contribution]
            struct Contribution: Codable, Sendable {
                let author: Author?
                struct Author: Codable, Sendable { let name: String }
            }
        }
    }
    static func fetchCurrentlyReading(forWidget: Bool) async -> [BookProgress] {
        LibrarySnapshot.load(status: 2)?.books ?? []
    }
    static func loadImagesForWidgets(books: inout [BookProgress]) async {}
    static func fetchReadingGoals() async -> [ReadingGoal] {
        do { return try await WidgetBackend.shared.goals() }
        catch { HardcoverReadScope.failure?.record(error); return [] }
    }
    static func fetchUpcomingReleasesFromWantToRead(limit: Int) async -> [UpcomingRelease] { [] }
}
enum LibraryAPI {
    static let fields = "id"
    struct User: Sendable { let id: Int }
    static func identity() async throws -> User { User(id: 1) }
    static func request(_ query: String, variables: [String: Any]) async throws -> Data {
        Data(#"{"data":{"reading_journals":[]}}"#.utf8)
    }
    static func makeBook(_ row: BookProgress) -> BookProgress? { row }
}
struct GraphQLUserBooksResponse: Decodable {
    struct Value: Decodable { let user_books: [BookProgress]? }
    let data: Value?
}
actor WidgetBackend {
    static let shared = WidgetBackend()
    private var calls = 0
    private var fail = false
    private var values = [ReadingGoal(id: 1)]
    private var delay: UInt64 = 0
    func configure(fail: Bool = false, values: [ReadingGoal] = [ReadingGoal(id: 1)], delay: UInt64 = 0) {
        self.fail = fail; self.values = values; self.delay = delay; calls = 0
    }
    func count() -> Int { calls }
    func goals() async throws -> [ReadingGoal] {
        calls += 1
        let result = values
        let fails = fail
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if fails { throw HardcoverNetworkError.server(503) }
        return result
    }
}
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date()
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
}
final class ReloadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var kinds: [String] = []
    private var statuses: [[Int]] = []
    func reload(_ kind: String) { lock.lock(); defer { lock.unlock() }; kinds.append(kind) }
    func notify(_ value: [Int]) { lock.lock(); defer { lock.unlock() }; statuses.append(value) }
    func snapshot() -> ([String], [[Int]]) { lock.lock(); defer { lock.unlock() }; return (kinds, statuses) }
}
// Disk policy tests use bytes directly. Image decoding/downsampling remains covered by iOS compilation.
struct UIImage: Sendable {
    enum Alpha { case first, last, premultipliedFirst, premultipliedLast, none }
    struct CGImage { let alphaInfo = Alpha.none }
    let data: Data
    var cgImage: CGImage? { nil }
    init?(data: Data) { self.data = data }
    func pngData() -> Data? { data }
    func jpegData(compressionQuality: Double) -> Data? { data }
}
