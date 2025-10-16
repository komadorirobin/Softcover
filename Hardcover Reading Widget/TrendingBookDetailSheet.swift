import SwiftUI
import Foundation

// Small read-only star row used in the header and reviews
private struct TrendingReadOnlyStars: View {
    let rating: Double // 0…5
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let threshold = Double(i) + 1.0
                if rating >= threshold {
                    Image(systemName: "star.fill")
                        .foregroundColor(.orange)
                } else if rating + 0.5 >= threshold {
                    if UIImage(systemName: "star.leadinghalf.filled") != nil {
                        Image(systemName: "star.leadinghalf.filled")
                            .foregroundColor(.orange)
                    } else {
                        ZStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.orange)
                                .mask(
                                    Rectangle()
                                        .frame(width: 6, height: 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                )
                            Image(systemName: "star")
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Image(systemName: "star")
                        .foregroundColor(.orange)
                }
            }
        }
        .font(.caption)
    }
}

// Inline review row with like/unlike
private struct TrendingInlineReviewRow: View {
    let review: HardcoverService.PublicReview
    
    @State private var likesCount: Int
    @State private var userHasLiked: Bool
    @State private var isLiking: Bool = false
    
    init(review: HardcoverService.PublicReview) {
        self.review = review
        _likesCount = State(initialValue: review.likesCount)
        _userHasLiked = State(initialValue: review.userHasLiked)
    }
    
    private func formattedDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let name = review.username, !name.isEmpty {
                    Text("@\(name)")
                        .font(.caption)
                        .fontWeight(.semibold)
                } else {
                    Text("Review")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text(formattedDate(review.reviewedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let r = review.rating {
                TrendingReadOnlyStars(rating: r)
            }
            
            if let text = review.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack(spacing: 8) {
                Spacer()
                Button {
                    Task { await toggleLike() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: userHasLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .imageScale(.small)
                        Text("\(likesCount)")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isLiking)
                .accessibilityLabel(userHasLiked ? Text("Unlike review") : Text("Like review"))
                .accessibilityValue(Text("\(likesCount)"))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    private func toggleLike() async {
        guard !isLiking else { return }
        let wasLiked = userHasLiked
        let newLikeState = !wasLiked
        
        await MainActor.run {
            isLiking = true
            // Optimistic update
            userHasLiked = newLikeState
            likesCount = max(0, likesCount + (newLikeState ? 1 : -1))
        }
        
        let result = await setLike(likeableId: review.id, like: newLikeState, likeableType: "UserBook")
        
        await MainActor.run {
            if let result {
                likesCount = max(0, result.likesCount)
                userHasLiked = result.didLike
#if os(iOS) && !targetEnvironment(macCatalyst)
                if userHasLiked {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
#endif
            } else {
                // Roll back
                userHasLiked = wasLiked
                likesCount = max(0, likesCount + (wasLiked ? 1 : -1))
            }
            isLiking = false
        }
    }
    
    // Local like helpers (mirrors HardcoverService+LikesToggle)
    private func setLike(likeableId: Int, like: Bool, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        if like { return await upsertLike(likeableId: likeableId, likeableType: likeableType) }
        else { return await deleteLike(likeableId: likeableId, likeableType: likeableType) }
    }
    
    private func upsertLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let mutation = """
        mutation UpsertLike($likeableId: Int!, $likeableType: String!) {
          likeResult: upsert_like(likeable_id: $likeableId, likeable_type: $likeableType) {
            likesCount: likes_count
            __typename
          }
        }
        """
        let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["errors"] as? [[String: Any]])?.isEmpty != false,
                  let dataDict = root["data"] as? [String: Any],
                  let likeResult = dataDict["likeResult"] as? [String: Any],
                  let likesCount = likeResult["likesCount"] as? Int else { return nil }
            return (max(0, likesCount), true)
        } catch { return nil }
    }
    
    private func deleteLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let mutation = """
        mutation DeleteLike($likeableId: Int!, $likeableType: String!) {
          likeResult: delete_like(likeable_id: $likeableId, likeable_type: $likeableType) {
            likesCount: likes_count
            __typename
          }
        }
        """
        let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["errors"] as? [[String: Any]])?.isEmpty != false,
                  let dataDict = root["data"] as? [String: Any],
                  let likeResult = dataDict["likeResult"] as? [String: Any],
                  let likesCount = likeResult["likesCount"] as? Int else { return nil }
            return (max(0, likesCount), false)
        } catch { return nil }
    }
}

// MARK: - Rich detail view for Trending (with Genres, Moods, Reviews)
struct TrendingBookDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: HardcoverService.TrendingBook
    let isWorking: Bool
    let onAddWithEdition: (Int?) -> Void
    
    // Genres & Moods state
    @State private var genres: [String] = []
    @State private var moods: [String] = []
    @State private var isLoadingGenres = false
    @State private var isLoadingMoods = false
    
    // Reviews state
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @State private var reviews: [HardcoverService.PublicReview] = []
    @State private var reviewsPage = 0
    private let reviewsPageSize = 10
    @State private var canLoadMoreReviews = true
    
    // Edition picker state (local to detail sheet)
    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false
    @State private var showingEditionSheet = false
    @State private var isLoadingEditions = false
    @State private var editions: [Edition] = []
    @State private var selectedEditionId: Int?
    
    // Description state
    @State private var bookDescription: String? = nil
    @State private var isLoadingDescription = false
    
    // Average rating state (book-level fallback)
    @State private var averageRating: Double? = nil
    
    // Read status
    @State private var isFinished = false
    @State private var finishedDate: Date?
    @State private var isLoadingFinishedStatus = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(alignment: .top, spacing: 16) {
                        if let urlString = item.coverImageUrl, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 140)
                                        .clipped()
                                        .cornerRadius(8)
                                        .shadow(radius: 3)
                                case .empty, .failure:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 100, height: 140)
                                        .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
                                @unknown default:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 100, height: 140)
                                }
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(width: 100, height: 140)
                                .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(3)
                            Text(item.author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            if let avg = averageRating {
                                HStack(spacing: 8) {
                                    TrendingReadOnlyStars(rating: avg)
                                    Text(String(format: NSLocalizedString("Average %.1f", comment: ""), avg))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if !genres.isEmpty {
                                WrapChipsView(items: genres)
                                    .padding(.top, 2)
                            } else if isLoadingGenres {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text(NSLocalizedString("Loading genres…", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 2)
                            }
                            
                            if !genres.isEmpty && !moods.isEmpty {
                                Divider().padding(.vertical, 2)
                            }
                            
                            if !moods.isEmpty {
                                WrapChipsView(items: moods)
                            } else if isLoadingMoods {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text(NSLocalizedString("Loading moods…", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Show read status if finished
                    if isFinished {
                        BookReadStatusView(finishedDate: finishedDate)
                    }
                    
                    // Quick action - only show if not finished
                    if !isFinished {
                        Button(action: {
                        if skipEditionPickerOnAdd {
                            onAddWithEdition(nil)
                            return
                        }
                        isLoadingEditions = true
                        Task {
                            let fetched = await HardcoverService.fetchEditions(for: item.id)
                            await MainActor.run {
                                isLoadingEditions = false
                                if fetched.count <= 1 {
                                    onAddWithEdition(fetched.first?.id)
                                } else {
                                    editions = fetched
                                    selectedEditionId = fetched.first?.id
                                    showingEditionSheet = true
                                }
                            }
                        }
                    }) {
                        if isWorking || isLoadingEditions {
                            HStack {
                                Spacer()
                                ProgressView().scaleEffect(0.9)
                                Spacer()
                            }
                        } else {
                            Label(NSLocalizedString("Add to Want to Read", comment: ""), systemImage: "bookmark.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || isLoadingEditions)
                    }
                    
                    // Description
                    if let desc = normalizedDescription(bookDescription) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            Text(desc)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.top, 4)
                    } else if isLoadingDescription {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text(NSLocalizedString("Loading description…", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Reviews
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reviews")
                                .font(.headline)
                            Spacer()
                            if isLoadingReviews {
                                ProgressView().scaleEffect(0.9)
                            }
                        }
                        
                        if let err = reviewsError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if reviews.isEmpty && !isLoadingReviews {
                            Text("No reviews found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(reviews) { r in
                                    TrendingInlineReviewRow(review: r)
                                }
                                if canLoadMoreReviews {
                                    HStack {
                                        Spacer()
                                        Button {
                                            Task { await loadMoreReviews(for: item.id) }
                                        } label: {
                                            if isLoadingReviews {
                                                ProgressView().scaleEffect(0.9)
                                            } else {
                                                Text("Load more")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        Spacer()
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("")
        }
        .sheet(isPresented: $showingEditionSheet) {
            EditionSelectionSheet(
                bookTitle: item.title,
                currentEditionId: selectedEditionId,
                editions: editions,
                onCancel: {
                    showingEditionSheet = false
                },
                onSave: { chosenId in
                    showingEditionSheet = false
                    onAddWithEdition(chosenId)
                }
            )
        }
        .task {
            await reloadTaxonomies()
            await reloadReviews(for: item.id)
            await loadDescription()
            await loadFinishedStatus()
            if averageRating == nil {
                averageRating = await fetchBookAverageRating(bookId: item.id)
            }
        }
    }
    
    // MARK: Reviews loading
    private func reloadReviews(for bookId: Int) async {
        await MainActor.run {
            isLoadingReviews = true
            reviewsError = nil
            reviewsPage = 0
            canLoadMoreReviews = true
            reviews = []
        }
        let list = await HardcoverService.fetchPublicReviewsForBook(bookId: bookId, limit: reviewsPageSize, offset: 0)
        await MainActor.run {
            isLoadingReviews = false
            reviews = list
            canLoadMoreReviews = list.count == reviewsPageSize
            reviewsPage = 1
        }
    }
    
    private func loadMoreReviews(for bookId: Int) async {
        guard !isLoadingReviews, canLoadMoreReviews else { return }
        await MainActor.run { isLoadingReviews = true }
        let offset = reviewsPage * reviewsPageSize
        let list = await HardcoverService.fetchPublicReviewsForBook(bookId: bookId, limit: reviewsPageSize, offset: offset)
        await MainActor.run {
            isLoadingReviews = false
            if list.isEmpty {
                canLoadMoreReviews = false
            } else {
                reviews.append(contentsOf: list)
                reviewsPage += 1
                if list.count < reviewsPageSize { canLoadMoreReviews = false }
            }
        }
    }
    
    // MARK: Genres & Moods loading
    private func reloadTaxonomies() async {
        await MainActor.run {
            if genres.isEmpty { isLoadingGenres = true }
            if moods.isEmpty { isLoadingMoods = true }
        }
        async let g = fetchGenresPreferred(bookId: item.id, userBookId: nil)
        async let m = fetchMoodsPreferred(bookId: item.id, editionId: nil, userBookId: nil)
        let (gList, mList) = await (g, m)
        await MainActor.run {
            self.genres = gList
            self.moods = mList
            self.isLoadingGenres = false
            self.isLoadingMoods = false
        }
    }
    
    private func loadDescription() async {
        await MainActor.run { isLoadingDescription = true }
        let detail = await HardcoverService.fetchBookDetailsById(bookId: item.id, userBookId: nil, imageMaxPixel: 360, compression: 0.8)
        await MainActor.run {
            isLoadingDescription = false
            bookDescription = detail?.bookDescription
        }
    }
    
    private func normalizedDescription(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty else { return nil }
        let withoutTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return withoutTags.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    // MARK: - Taxonomy helpers (delegate to BookMetadataService)
    private func fetchGenresPreferred(bookId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        if let bid = bookId {
            if let arr = await BookMetadataService.queryBookCachedGenres(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await BookMetadataService.queryUserBookCachedGenres(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        return []
    }
    
    private func fetchMoodsPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        if let bid = bookId {
            if let arr = await BookMetadataService.queryBookMoodsViaTaggings(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await BookMetadataService.queryEditionBookMoodsViaTaggings(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await BookMetadataService.queryUserBookMoodsViaTaggings(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let bid = bookId {
            if let arr = await BookMetadataService.queryBookCachedMoods(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await BookMetadataService.queryEditionBookCachedMoods(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await BookMetadataService.queryUserBookCachedMoods(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        return []
    }
    
    // MARK: - Load finished status
    private func loadFinishedStatus() async {
        await MainActor.run { isLoadingFinishedStatus = true }
        
        let metadataService = BookMetadataService()
        let finishedDatesDict = await metadataService.fetchFinishedBooksWithDates(for: [item.id])
        
        // Fallback: markera som läst även utan datum
        var finishedFlag = finishedDatesDict[item.id] != nil
        var dateValue = finishedDatesDict[item.id]
        if !finishedFlag {
            let finishedIds = await metadataService.fetchFinishedBookIds(for: [item.id])
            if finishedIds.contains(item.id) {
                finishedFlag = true
                dateValue = nil
            }
        }
        
        await MainActor.run {
            isLoadingFinishedStatus = false
            isFinished = finishedFlag
            finishedDate = dateValue
        }
    }
    
    // MARK: - Fetch average rating (book-level)
    private func fetchBookAverageRating(bookId: Int) async -> Double? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            rating
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["id": bookId]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return first["rating"] as? Double
            }
        } catch {
            return nil
        }
        return nil
    }
}
