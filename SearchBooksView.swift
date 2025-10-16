import SwiftUI
import Foundation

struct SearchBooksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var isSearching = false
    @State private var results: [HydratedBook] = []
    @State private var errorMessage: String?
    
    // Read flags for search results
    @State private var finishedBookIds: Set<Int> = []
    @State private var readDates: [Int: Date] = [:]
    
    // Trending state
    @State private var trending: [HardcoverService.TrendingBook] = []
    @State private var trendingLoading = false
    @State private var trendingError: String?
    @State private var trendingAddInProgress: Int?
    @State private var selectedTrending: HardcoverService.TrendingBook?
    
    // Search detail state
    @State private var selectedSearchDetail: BookProgress?
    
    // Quick-add state
    @State private var rowAddInProgress: Int?
    @State private var quickAddPendingBook: HydratedBook?
    @State private var quickAddEditions: [Edition] = []
    @State private var quickAddSelectedEditionId: Int?
    @State private var showingQuickAddEditionSheet = false
    @State private var isLoadingQuickAddEditions = false

    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false

    // Services
    private let metadataService = BookMetadataService()
    private let tagExtractor = BookTagExtractor()

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                SearchHeaderView(
                    query: $query,
                    isSearching: isSearching,
                    onSearch: { Task { await runSearch() } }
                )
                .padding(.horizontal)
                .padding(.top)

                if results.isEmpty {
                    TrendingSectionView(
                        trending: trending,
                        trendingLoading: trendingLoading,
                        trendingError: trendingError,
                        trendingAddInProgress: trendingAddInProgress,
                        selectedTrending: $selectedTrending,
                        onAddTrending: { item in Task { await addTrendingBook(item) } },
                        onReloadTrending: { Task { await loadTrending(force: true) } }
                    )
                } else {
                    SearchResultsListView(
                        results: results,
                        finishedBookIds: finishedBookIds,
                        readDates: readDates,
                        rowAddInProgress: rowAddInProgress,
                        isLoadingQuickAddEditions: isLoadingQuickAddEditions,
                        onQuickAdd: { book in Task { await quickAddWantToReadFlow(book) } },
                        onTapResult: { book in Task { await openDetails(for: book) } }
                    )
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadTrending(force: false) }
        .sheet(item: $selectedTrending) { item in
            TrendingBookDetailSheet(
                item: item,
                isWorking: trendingAddInProgress == item.id,
                onAddWithEdition: { chosenId in
                    Task { await addTrendingBook(item, editionId: chosenId) }
                }
            )
        }
        .sheet(item: $selectedSearchDetail) { book in
            SearchResultDetailSheet(
                book: book,
                onAddComplete: { success in
                    if success {
                        onDone(true)
                        dismiss()
                    }
                }
            )
        }
        .sheet(isPresented: $showingQuickAddEditionSheet) {
            if let pending = quickAddPendingBook {
                EditionSelectionSheet(
                    bookTitle: pending.title,
                    currentEditionId: quickAddSelectedEditionId,
                    editions: quickAddEditions,
                    onCancel: {
                        quickAddPendingBook = nil
                        quickAddEditions = []
                        quickAddSelectedEditionId = nil
                    },
                    onSave: { chosenId in
                        Task {
                            await addSearchResultToWantToRead(pending, editionId: chosenId)
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func runSearch() async {
        errorMessage = nil
        let raw = query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let (titlePart, authorPart) = parseQuery(raw)
        
        isSearching = true
        let list = await HardcoverService.searchBooks(
            title: titlePart,
            author: authorPart?.isEmpty == false ? authorPart : nil
        )
        await MainActor.run {
            self.results = list
            self.isSearching = false
            if list.isEmpty {
                self.errorMessage = "No results. Try another search."
            }
        }
        await refreshFinishedFlags()
    }
    
    private func refreshFinishedFlags() async {
        let ids = results.map { $0.id }
        guard !ids.isEmpty else {
            await MainActor.run { 
                finishedBookIds = []
                readDates = [:]
            }
            return
        }
        let finishedDatesDict = await metadataService.fetchFinishedBooksWithDates(for: ids)
        await MainActor.run { 
            finishedBookIds = Set(finishedDatesDict.keys)
            readDates = finishedDatesDict
        }
    }
    
    private func parseQuery(_ q: String) -> (title: String, author: String?) {
        let lower = q.lowercased()
        guard let range = lower.range(of: "author:") else {
            return (q, nil)
        }
        let authorStartIndex = range.upperBound
        let titlePart = q[..<range.lowerBound].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let authorRaw = q[authorStartIndex...].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        if authorRaw.hasPrefix("\"") {
            if let endQuote = authorRaw.dropFirst().firstIndex(of: "\"") {
                let name = authorRaw[authorRaw.index(after: authorRaw.startIndex)..<endQuote]
                return (titlePart, String(name).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            } else {
                return (titlePart, String(authorRaw.dropFirst()).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            }
        } else {
            return (titlePart, authorRaw)
        }
    }
    
    // NYTT: Open details for a search result
    private func openDetails(for book: HydratedBook) async {
        // Försök hämta en BookProgress med beskrivning (om möjligt) för en rik detaljvy
        let detail = await HardcoverService.fetchBookDetailsById(bookId: book.id, userBookId: nil, imageMaxPixel: 360, compression: 0.8)
        await MainActor.run {
            if let detail {
                selectedSearchDetail = detail
            } else {
                // Fallback: minimalt objekt om hämtning misslyckas
                let author = book.contributions?.first?.author?.name ?? "Unknown Author"
                let minimal = BookProgress(
                    id: "search-\(book.id)",
                    title: book.title,
                    author: author,
                    coverImageData: nil,
                    progress: 0.0,
                    totalPages: 0,
                    currentPage: 0,
                    bookId: book.id,
                    userBookId: nil,
                    editionId: nil,
                    originalTitle: book.title,
                    editionAverageRating: nil,
                    userRating: nil,
                    bookDescription: nil
                )
                selectedSearchDetail = minimal
            }
        }
    }
    
    private func loadTrending(force: Bool) async {
        guard force || trending.isEmpty else { return }
        await MainActor.run {
            trendingLoading = true
            trendingError = nil
        }
        // Endast månadens trending. Ingen fallback till all-time här.
        let list = await HardcoverService.fetchTrendingBooksMonthly(limit: 20, imageMaxPixel: 280, compression: 0.75)
        await MainActor.run {
            trendingLoading = false
            trending = list
            if list.isEmpty {
                trendingError = NSLocalizedString("Trending is not available right now.", comment: "")
            }
        }
    }
    
    private func addTrendingBook(_ item: HardcoverService.TrendingBook) async {
        await MainActor.run { trendingAddInProgress = item.id }
        
        // If user prefers to skip edition picker, add immediately (no edition)
        if skipEditionPickerOnAdd {
            let ok = await HardcoverService.addBookToWantToRead(bookId: item.id, editionId: nil)
            await MainActor.run {
                trendingAddInProgress = nil
                if ok {
                    onDone(true)
                    dismiss()
                } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
                }
            }
            return
        }
        
        // Otherwise, fetch editions and present picker when there are multiple
        await MainActor.run { isLoadingQuickAddEditions = true }
        let editions = await HardcoverService.fetchEditions(for: item.id)
        if editions.count <= 1 {
            let chosenId = editions.first?.id
            let ok = await HardcoverService.addBookToWantToRead(bookId: item.id, editionId: chosenId)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                trendingAddInProgress = nil
                if ok {
                    onDone(true)
                    dismiss()
                } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
                }
            }
        } else {
            await MainActor.run {
                quickAddPendingBook = HydratedBook(
                    id: item.id,
                    title: item.title,
                    contributions: nil,
                    image: nil
                )
                quickAddEditions = editions
                quickAddSelectedEditionId = editions.first?.id
                isLoadingQuickAddEditions = false
                showingQuickAddEditionSheet = true
                trendingAddInProgress = nil
            }
        }
    }
    
    // Overload used by detail sheet to add with a specific edition id
    private func addTrendingBook(_ item: HardcoverService.TrendingBook, editionId: Int?) async {
        await MainActor.run { trendingAddInProgress = item.id }
        let ok = await HardcoverService.addBookToWantToRead(bookId: item.id, editionId: editionId)
        await MainActor.run {
            trendingAddInProgress = nil
            if ok {
                onDone(true)
                dismiss()
            } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
            }
        }
    }
    
    // MARK: - NYTT: Snabb-add med editionsflöde
    private func quickAddWantToReadFlow(_ book: HydratedBook) async {
        // If user prefers to skip edition selection, add immediately with default (nil editionId)
        if skipEditionPickerOnAdd {
            await MainActor.run { rowAddInProgress = book.id }
            await addSearchResultToWantToRead(book, editionId: nil)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                rowAddInProgress = nil
            }
            return
        }
        
        await MainActor.run {
            rowAddInProgress = book.id
            isLoadingQuickAddEditions = true
            quickAddPendingBook = nil
            quickAddEditions = []
            quickAddSelectedEditionId = nil
        }
        // Hämta utgåvor
        let editions = await HardcoverService.fetchEditions(for: book.id)
        // Om 0–1 utgåvor -> lägg till direkt
        if editions.count <= 1 {
            let eid = editions.first?.id
            await addSearchResultToWantToRead(book, editionId: eid)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                rowAddInProgress = nil
            }
            return
        }
        // Fler än en utgåva -> öppna väljare
        await MainActor.run {
            isLoadingQuickAddEditions = false
            rowAddInProgress = nil
            quickAddPendingBook = book
            quickAddEditions = editions
            quickAddSelectedEditionId = nil
            showingQuickAddEditionSheet = true
        }
    }
    
    // Ursprungliga snabb-add funktionen – nu återanvänd med explicit editionId
    private func addSearchResultToWantToRead(_ book: HydratedBook, editionId: Int?) async {
        await MainActor.run { rowAddInProgress = book.id }
        let ok = await HardcoverService.addBookToWantToRead(bookId: book.id, editionId: editionId)
        await MainActor.run {
            rowAddInProgress = nil
            if ok {
                onDone(true)
                dismiss()
            } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
            }
            // Stäng ev. quick-add-sheet state
            showingQuickAddEditionSheet = false
            quickAddPendingBook = nil
            quickAddEditions = []
            quickAddSelectedEditionId = nil
        }
    }
}

// Small helper view for the refresh icon/loader in Trending header
private struct IfTrendingLoadingView: View {
    let trendingLoading: Bool
    let onReload: () -> Void
    var body: some View {
        if trendingLoading {
            ProgressView().scaleEffect(0.8)
        } else {
            Button(action: onReload) {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Reload trending")
        }
    }
}

// MARK: - UI Components (Trending)
private struct TrendingBookCell: View {
    let item: HardcoverService.TrendingBook
    let isWorking: Bool
    let onTap: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            if let data = item.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 112)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(radius: 2)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 80, height: 112)
                    .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
            }
            Text(item.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .frame(width: 80, alignment: .leading)
            Text(item.author)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
            
            Spacer(minLength: 0) // Tryck ner plus-knappen till botten
            
            Button(action: onTap) {
                if isWorking {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.accentColor)
        }
        .frame(width: 100, height: 190, alignment: .top) // Fast höjd så alla celler får samma botten
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}

private struct TrendingSkeletonCell: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 112)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 10)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 40, height: 22)
        }
        .redacted(reason: .placeholder)
        .frame(width: 100, height: 190, alignment: .top)
    }
}

// Inline review row used in TrendingBookDetailSheet
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
            
            // Like row
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
            if newLikeState {
                likesCount += 1
            } else {
                likesCount = max(0, likesCount - 1)
            }
        }
        
        // Local helper to avoid cross-target dependency on HardcoverService extension
        let result = await setLike(likeableId: review.id, like: newLikeState, likeableType: "UserBook")
        
        await MainActor.run {
            if let result {
                // Update with confirmed state from server
                likesCount = max(0, result.likesCount)
                userHasLiked = result.didLike
#if os(iOS) && !targetEnvironment(macCatalyst)
                if userHasLiked {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
#endif
            } else {
                // Rollback on failure
                userHasLiked = wasLiked
                if wasLiked {
                    likesCount += 1
                } else {
                    likesCount = max(0, likesCount - 1)
                }
            }
            isLiking = false
        }
    }
    
    // MARK: - Local like helpers (mirrors HardcoverService+LikesToggle)
    private func setLike(likeableId: Int, like: Bool, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        if like {
            return await upsertLike(likeableId: likeableId, likeableType: likeableType)
        } else {
            return await deleteLike(likeableId: likeableId, likeableType: likeableType)
        }
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

// MARK: - Flow layout (stabil höjd för chips)
private struct ChipsFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                // ny rad
                x = 0
                y += rowSpacing + rowHeight
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + (x > 0 ? spacing : 0)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                // ny rad
                x = bounds.minX
                y += rowSpacing + rowHeight
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// Wrap chips for genres and moods – använder ChipsFlowLayout så innehåll trycks ned korrekt
private struct WrapChipsView: View {
    let items: [String]
    var body: some View {
        ChipsFlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(items, id: \.self) { text in
                Text(text)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
            }
        }
    }
}

private struct ReadOnlyStars: View {
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
        .font(.caption) // Mindre stjärnor för medelbetyget i Trending-detaljvyn
    }
}

// MARK: - Rich detail view for Trending (with Genres, Moods and Reviews)
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
    
    // Read status state (to show "Läst (datum)" if already finished)
    @State private var isFinished: Bool = false
    @State private var finishedDate: Date? = nil
    @State private var isLoadingFinishedStatus: Bool = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        if let data = item.coverImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 140)
                                .clipped()
                                .cornerRadius(8)
                                .shadow(radius: 3)
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
                            
                            // Average rating row
                            if let avg = averageRating {
                                HStack(spacing: 8) {
                                    ReadOnlyStars(rating: avg)
                                    Text(String(format: NSLocalizedString("Average %.1f", comment: ""), avg))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Genres chips
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
                            
                            // Separator if both exist
                            if !genres.isEmpty && !moods.isEmpty {
                                Divider().padding(.vertical, 2)
                            }
                            
                            // Moods chips
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
                    
                    // If the book is already finished, show read status with date (from reading history)
                    if isFinished {
                        BookReadStatusView(finishedDate: finishedDate)
                    }
                    
                    // Quick action
                    Button(action: {
                        // Handle edition selection locally to avoid nested sheets
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
                    
                    // Description (if available)
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
            // Load average rating (book-level)
            if averageRating == nil {
                averageRating = await fetchBookAverageRating(bookId: item.id)
            }
            // Load finished status to show "Läst (datum)" if applicable
            await loadFinishedStatus()
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
    
    // MARK: Genres & Moods loading (samma logik som i sök-detaljvyn)
    private func reloadTaxonomies() async {
        await MainActor.run {
            if genres.isEmpty { isLoadingGenres = true }
            if moods.isEmpty { isLoadingMoods = true }
        }
        async let g = fetchGenresPreferred(bookId: item.id, editionId: nil, userBookId: nil)
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
    

    private func fetchGenresPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        // Curated only: cached_tags paths
        if let bid = bookId {
            if let arr = await queryBookCachedGenres(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookCachedGenres(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // No fallback to taggings to ensure only curated genres are shown
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
        
        // 1) Taggings path
        if let bid = bookId {
            if let arr = await queryBookMoodsViaTaggings(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await queryEditionBookMoodsViaTaggings(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookMoodsViaTaggings(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        
        // 2) cached_tags path
        if let bid = bookId {
            if let arr = await queryBookCachedMoods(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await queryEditionBookCachedMoods(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookCachedMoods(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        return []
    }
    

    
    // Find the most recent user_book id for the current user and given book
    private func fetchLatestUserBookIdForBook(bookId: Int) async -> Int? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        
        // 1) Fetch current user's id via { me { id } }
        var meRequest = URLRequest(url: url)
        meRequest.httpMethod = "POST"
        meRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        meRequest.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        meRequest.httpBody = "{ \"query\": \"{ me { id } }\" }".data(using: .utf8)
        var currentUserId: Int?
        do {
            let (meData, _) = try await URLSession.shared.data(for: meRequest)
            if let root = try JSONSerialization.jsonObject(with: meData) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let meArr = dataDict["me"] as? [[String: Any]],
               let me = meArr.first,
               let uid = me["id"] as? Int {
                currentUserId = uid
            }
        } catch {
            return nil
        }
        guard let userId = currentUserId else { return nil }
        
        // 2) Fetch latest user_book for this user and book
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($bookId: Int!, $userId: Int!) {
          user_books(
            where: { book_id: { _eq: $bookId }, user_id: { _eq: $userId } },
            order_by: { id: desc },
            limit: 1
          ) {
            id
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["bookId": bookId, "userId": userId]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { return nil }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first,
               let id = first["id"] as? Int {
                return id
            }
        } catch { return nil }
        return nil
    }
}

// A small star rating control with 0.5 increments (tap/long-press to toggle halves)
private struct StarRatingPicker: View {
    @Binding var rating: Double?
    
    private func starSymbol(for index: Int) -> String {
        guard let r = rating else { return "star" }
        let threshold = Double(index) + 1.0
        if r >= threshold {
            return "star.fill"
        } else if r + 0.5 >= threshold {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
    
    private func setRating(for index: Int) {
        // Toggle in 0.5 steps. Tap cycles: empty -> .5 -> 1.0 for the first star, etc.
        let base = Double(index) + 1.0
        if let r = rating {
            if r >= base {
                // currently full -> clear to nil if last star tapped, else drop to half
                rating = (abs(r - base) < 0.001) ? nil : (base - 0.5)
            } else if r + 0.5 >= base {
                // currently half -> bump to full
                rating = base
            } else {
                // below -> set to half
                rating = base - 0.5
            }
        } else {
            rating = base - 0.5
        }
        // Clamp 0…5
        if let r = rating {
            rating = min(5.0, max(0.5, (round(r * 2) / 2)))
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { idx in
                Image(systemName: starSymbol(for: idx))
                    .foregroundColor(.orange)
                    .font(.title3)
                    .onTapGesture {
                        setRating(for: idx)
                    }
                    .accessibilityLabel("Rate")
            }
            if let r = rating {
                Text("\(r, specifier: "%.1f")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading, 6)
            } else {
                Text("No rating")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating != nil ? "\(rating!, specifier: "%.1f") of 5" : "No rating")
    }
}

// MARK: - Review row with like/unlike for SearchResultDetailSheet
private struct SearchReviewRow: View {
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
                // Small stars, same look as Trending's inline
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        let threshold = Double(i) + 1.0
                        if r >= threshold {
                            Image(systemName: "star.fill").foregroundColor(.orange)
                        } else if r + 0.5 >= threshold {
                            Image(systemName: "star.leadinghalf.filled").foregroundColor(.orange)
                        } else {
                            Image(systemName: "star").foregroundColor(.orange.opacity(0.35))
                        }
                    }
                }
                .font(.caption)
                .accessibilityLabel("Rating")
                .accessibilityValue("\(r, specifier: "%.1f") of 5")
            }
            if let text = review.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Like row
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
            if newLikeState {
                likesCount += 1
            } else {
                likesCount = max(0, likesCount - 1)
            }
        }
        
        // Local helper to avoid cross-target dependency on HardcoverService extension
        let result = await setLike(likeableId: review.id, like: newLikeState, likeableType: "UserBook")
        
        await MainActor.run {
            if let result {
                // Update with confirmed state from server
                likesCount = max(0, result.likesCount)
                userHasLiked = result.didLike
#if os(iOS) && !targetEnvironment(macCatalyst)
                if userHasLiked {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
#endif
            } else {
                // Rollback on failure
                userHasLiked = wasLiked
                if wasLiked {
                    likesCount += 1
                } else {
                    likesCount = max(0, likesCount - 1)
                }
            }
            isLiking = false
        }
    }
    
    // MARK: - Local like helpers (mirrors HardcoverService+LikesToggle)
    private func setLike(likeableId: Int, like: Bool, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        if like {
            return await upsertLike(likeableId: likeableId, likeableType: likeableType)
        } else {
            return await deleteLike(likeableId: likeableId, likeableType: likeableType)
        }
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

// MARK: - UI helper for Trending header
private struct IfTrendingLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        IfTrendingLoadingView(trendingLoading: true, onReload: {})
    }
}

#Preview { SearchBooksView { _ in } }
