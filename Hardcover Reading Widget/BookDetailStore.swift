import SwiftUI

struct BookDetailMetadata: Equatable {
    let title: String
    let author: String
    let coverURL: String?
    let releaseDate: String?
    let description: String?
    let rating: Double?
    let genres: [String]
    let moods: [String]
}

@MainActor
final class BookDetailStore: ObservableObject {
    let bookID: Int?
    @Published private(set) var metadata: BookDetailMetadata?
    @Published private(set) var ownBook: BookProgress?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOwnBook = false
    @Published private(set) var error: String?
    @Published private(set) var personalError: String?
    @Published private(set) var reviews: [HardcoverService.PublicReview] = []
    @Published private(set) var reviewsError: String?
    @Published private(set) var loadingReviews = false
    @Published private(set) var hasMoreReviews = true
    @Published private(set) var quotes: [Quote] = []
    @Published private(set) var quotesError: String?
    @Published private(set) var loadingQuotes = false
    private var reviewsOffset = 0
    private var loadedReviews = false
    private var loadedQuotes = false
    private var account = ""
    private var metadataGeneration = UUID()
    private var personalGeneration = UUID()
    private var reviewsGeneration = UUID()
    private var quotesGeneration = UUID()

    init(bookID: Int?) { self.bookID = bookID }

    // LibraryAPI caches and coalesces the entire successful response, including empty tags.
    static let metadataQuery = BookDetailQueries.metadata

    func load(fresh: Bool = false) async {
        resetIfAccountChanged()
        let auth = account
        guard let bookID else { return }
        let generation = UUID()
        metadataGeneration = generation
        isLoading = true
        error = nil
        defer { if isCurrent(auth), metadataGeneration == generation { isLoading = false } }
        await refreshOwnBook(fresh: fresh)
        guard metadataGeneration == generation, isCurrent(auth), !Task.isCancelled else { return }
        do {
            let data = try await LibraryAPI.request(Self.metadataQuery, variables: ["id": bookID], fresh: fresh)
            guard isCurrent(auth), metadataGeneration == generation, !Task.isCancelled else { return }
            metadata = try Self.decodeMetadata(data)
        } catch is CancellationError { }
        catch { if isCurrent(auth), metadataGeneration == generation { self.error = error.localizedDescription } }
    }

    static func decodeMetadata(_ data: Data) throws -> BookDetailMetadata {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["data"] as? [String: Any],
              let book = (content["books"] as? [[String: Any]])?.first else {
            throw HardcoverNetworkError.invalidResponse
        }
        let description = (book["description"] as? String)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
        return BookDetailMetadata(
            title: book["title"] as? String ?? "",
            author: (book["cached_contributors"] as? [[String: Any]] ?? []).compactMap {
                ($0["author"] as? [String: Any])?["name"] as? String ?? $0["name"] as? String
            }.joined(separator: ", "),
            coverURL: (book["image"] as? [String: Any])?["url"] as? String,
            releaseDate: book["release_date"] as? String,
            description: description?.isEmpty == false ? description : nil,
            rating: book["rating"] as? Double,
            genres: BookTagExtractor.extractGenres(fromCachedTags: book["cached_tags"]) ?? [],
            moods: BookTagExtractor.extractMoods(fromCachedTags: book["cached_tags"]) ?? []
        )
    }

    func refreshOwnBook(fresh: Bool = true) async {
        resetIfAccountChanged()
        let auth = account
        guard let bookID else { return }
        let generation = UUID()
        personalGeneration = generation
        personalError = nil
        do {
            let value = try await LibraryAPI.ownBook(bookID: bookID, fresh: fresh)
            guard isCurrent(auth), personalGeneration == generation, !Task.isCancelled else { return }
            ownBook = value
            hasLoadedOwnBook = true
        } catch is CancellationError { }
        catch { if isCurrent(auth), personalGeneration == generation { personalError = error.localizedDescription } }
    }

    func apply(_ book: BookProgress) {
        guard account == HardcoverConfig.authorizationHeaderValue else { return }
        personalGeneration = UUID()
        ownBook = book
        hasLoadedOwnBook = true
    }

    func loadReviews(more: Bool = false, fresh: Bool = false) async {
        resetIfAccountChanged()
        guard let bookID, !loadingReviews || fresh, fresh || more || !loadedReviews else { return }
        guard !more || hasMoreReviews else { return }
        let auth = account
        let generation = UUID()
        reviewsGeneration = generation
        loadingReviews = true
        reviewsError = nil
        let offset = more ? reviewsOffset : 0
        defer { if isCurrent(auth), reviewsGeneration == generation { loadingReviews = false } }
        do {
            let data = try await LibraryAPI.request(Self.reviewsQuery, variables: ["bookID": bookID, "offset": offset], fresh: fresh)
            struct Row: Decodable {
                struct User: Decodable { let username: String? }
                let id: Int
                let rating: Double?
                let reviewed_at: String?
                let review_raw: String?
                let user: User?
            }
            struct Response: Decodable { struct Value: Decodable { let user_books: [Row] }; let data: Value }
            let rows = try JSONDecoder().decode(Response.self, from: data).data.user_books
            let likes = try await loadReviewLikes(ids: rows.map(\.id))
            guard isCurrent(auth), reviewsGeneration == generation, !Task.isCancelled else { return }
            let list = rows.map {
                HardcoverService.PublicReview(id: $0.id, rating: $0.rating, reviewedAt: Self.timestamp($0.reviewed_at),
                    text: $0.review_raw, username: $0.user?.username, likesCount: likes[$0.id]?.0 ?? 0,
                    userHasLiked: likes[$0.id]?.1 ?? false)
            }
            var ids = Set<Int>()
            reviews = (more ? reviews + list : list).filter { ids.insert($0.id).inserted }
            reviewsOffset = offset + rows.count
            hasMoreReviews = rows.count == 10
            loadedReviews = true
        } catch is CancellationError { }
        catch { if isCurrent(auth), reviewsGeneration == generation { reviewsError = error.localizedDescription } }
    }

    private func loadReviewLikes(ids: [Int]) async throws -> [Int: (Int, Bool)] {
        guard !ids.isEmpty else { return [:] }
        let userID = try await LibraryAPI.identity().id
        let data = try await LibraryAPI.request(Self.reviewLikesQuery, variables: ["ids": ids, "userID": userID], cost: 2)
        struct Row: Decodable { let likeable_id: Int }
        struct Response: Decodable { struct Value: Decodable { let likes: [Row]; let mine: [Row] }; let data: Value }
        let value = try JSONDecoder().decode(Response.self, from: data).data
        let counts = Dictionary(grouping: value.likes, by: \.likeable_id).mapValues(\.count)
        let mine = Set(value.mine.map(\.likeable_id))
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, (counts[$0] ?? 0, mine.contains($0))) })
    }

    func loadQuotes(fresh: Bool = false) async {
        resetIfAccountChanged()
        guard let bookID, !loadingQuotes || fresh, fresh || !loadedQuotes else { return }
        let auth = account
        let generation = UUID()
        quotesGeneration = generation
        loadingQuotes = true
        quotesError = nil
        defer { if isCurrent(auth), quotesGeneration == generation { loadingQuotes = false } }
        do {
            let userID = try await LibraryAPI.identity().id
            let data = try await LibraryAPI.request(Self.quotesQuery, variables: ["bookID": bookID, "userID": userID], fresh: fresh)
            let list = try Quote.decodeBookResponse(data, bookID: bookID)
            guard isCurrent(auth), quotesGeneration == generation, !Task.isCancelled else { return }
            quotes = list
            loadedQuotes = true
        } catch is CancellationError { }
        catch { if isCurrent(auth), quotesGeneration == generation { quotesError = error.localizedDescription } }
    }

    static let reviewsQuery = BookDetailQueries.reviews
    static let reviewLikesQuery = BookDetailQueries.reviewLikes
    static let quotesQuery = BookDetailQueries.quotes

    private func resetIfAccountChanged() {
        let auth = HardcoverConfig.authorizationHeaderValue
        guard account != auth else { return }
        account = auth
        metadata = nil
        ownBook = nil
        hasLoadedOwnBook = false
        reviews = []
        quotes = []
        loadedReviews = false
        loadedQuotes = false
        loadingReviews = false
        loadingQuotes = false
        hasMoreReviews = true
        reviewsOffset = 0
        error = nil
        personalError = nil
        reviewsError = nil
        quotesError = nil
    }

    private func isCurrent(_ authorization: String) -> Bool {
        account == authorization && authorization == HardcoverConfig.authorizationHeaderValue
    }

    private static func timestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) ?? ReleaseDate.parse(value)
    }
}

enum BookPersonalActions {
    enum Failure: LocalizedError {
        case missingBook, saveFailed, editionChanged, progressChanged
        var errorDescription: String? {
            switch self {
            case .missingBook: return NSLocalizedString("This book is no longer in your library. Refresh and try again.", comment: "")
            case .saveFailed: return NSLocalizedString("The change could not be saved. Please try again.", comment: "")
            case .editionChanged: return NSLocalizedString("The edition or reading status has changed. Reopen the progress editor to continue.", comment: "")
            case .progressChanged: return NSLocalizedString("Reading progress changed on another device. Review the latest progress before saving.", comment: "")
            }
        }
    }

    static func requireOwnBook(bookID: Int?, authorization: String) async throws -> BookProgress {
        guard authorization == HardcoverConfig.authorizationHeaderValue else { throw HardcoverNetworkError.accountChanged }
        guard let bookID, let own = try await LibraryAPI.ownBook(bookID: bookID, fresh: true), own.userBookId != nil else {
            throw Failure.missingBook
        }
        try Task.checkCancellation()
        guard authorization == HardcoverConfig.authorizationHeaderValue else { throw HardcoverNetworkError.accountChanged }
        return own
    }
}
