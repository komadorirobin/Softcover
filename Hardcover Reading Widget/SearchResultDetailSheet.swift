import SwiftUI
import Foundation

struct SearchResultDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let book: BookProgress
    let onAddComplete: (Bool) -> Void
    
    // UI state
    @State private var isWorking = false
    @State private var isWorkingReading = false
    @State private var isWorkingFinished = false
    
    // Book details
    @State private var bookDescription: String?
    @State private var isLoadingDescription = false
    
    // Edition selection
    private enum PendingAction { case wantToRead, readNow, markAsRead }
    @State private var pendingAction: PendingAction?
    @State private var editions: [Edition] = []
    @State private var isLoadingEditions = false
    @State private var selectedEditionId: Int?
    @State private var showingEditionSheet = false
    
    // Rating sheet state
    @State private var showingRatingSheet = false
    @State private var isCreatingUserBook = false
    @State private var ratingSheetUserBookId: Int? = nil
    
    // Taxonomies
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
    
    // Read status
    @State private var isFinished = false
    @State private var finishedDate: Date?
    @State private var isLoadingFinishedStatus = false

    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Book header with cover and metadata
                    BookHeaderView(
                        book: book,
                        genres: genres,
                        moods: moods,
                        isLoadingGenres: isLoadingGenres,
                        isLoadingMoods: isLoadingMoods
                    )
                    
                    // Quick actions - only show if not finished
                    if !isFinished {
                        BookActionsView(
                            book: book,
                            isWorking: isWorking,
                            isWorkingReading: isWorkingReading,
                            isWorkingFinished: isWorkingFinished,
                            isLoadingEditions: isLoadingEditions,
                            onWantToRead: { Task { await ensureEditionThenPerform(.wantToRead) } },
                            onReadNow: { Task { await ensureEditionThenPerform(.readNow) } },
                            onMarkAsRead: { Task { await ensureEditionThenPerform(.markAsRead) } }
                        )
                    } else {
                        // Show read status
                        BookReadStatusView(finishedDate: finishedDate)
                    }
                    
                    // Rate & Review section
                    RateReviewSection(
                        book: book,
                        selectedEditionId: selectedEditionId,
                        isCreatingUserBook: isCreatingUserBook,
                        ratingSheetUserBookId: $ratingSheetUserBookId,
                        showingRatingSheet: $showingRatingSheet,
                        onCreateEntry: { await createUserBookEntry() }
                    )
                    
                    // Description
                    if let desc = normalizedDescription(bookDescription ?? book.bookDescription) {
                        BookDescriptionView(description: desc)
                    } else if isLoadingDescription {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Loading description...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                    
                    // Reviews
                    ReviewsSection(
                        reviews: reviews,
                        isLoadingReviews: isLoadingReviews,
                        reviewsError: reviewsError,
                        canLoadMoreReviews: canLoadMoreReviews,
                        onLoadMore: { Task { await loadMoreReviews() } }
                    )
                }
                .padding()
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await loadInitialData()
        }
        .sheet(isPresented: $showingEditionSheet) {
            if !editions.isEmpty {
                EditionSelectionSheet(
                    bookTitle: book.title,
                    currentEditionId: selectedEditionId,
                    editions: editions,
                    onCancel: {
                        pendingAction = nil
                        selectedEditionId = nil
                    },
                    onSave: { chosenId in
                        selectedEditionId = chosenId
                        Task { await performPendingAction() }
                    }
                )
            }
        }
        .sheet(isPresented: $showingRatingSheet) {
            if let userBookId = ratingSheetUserBookId {
                BookRatingSheet(userBookId: userBookId) {
                    showingRatingSheet = false
                    ratingSheetUserBookId = nil
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadBookDescription() }
            group.addTask { await loadGenres() }
            group.addTask { await loadMoods() }
            group.addTask { await loadReviews() }
            group.addTask { await loadFinishedStatus() }
        }
    }
    
    private func ensureEditionThenPerform(_ action: PendingAction) async {
        pendingAction = action
        
        if skipEditionPickerOnAdd {
            await performPendingAction()
            return
        }
        
        await MainActor.run { isLoadingEditions = true }
        
        guard let bookId = book.bookId else {
            await MainActor.run { isLoadingEditions = false }
            return
        }
        
        let fetchedEditions = await HardcoverService.fetchEditions(for: bookId)
        
        await MainActor.run {
            isLoadingEditions = false
            editions = fetchedEditions
            
            if editions.count <= 1 {
                selectedEditionId = editions.first?.id
                Task { await performPendingAction() }
            } else {
                showingEditionSheet = true
            }
        }
    }
    
    private func performPendingAction() async {
        guard let action = pendingAction else { return }
        
        switch action {
        case .wantToRead:
            await addToWantToRead()
        case .readNow:
            await startReading()
        case .markAsRead:
            await markAsFinished()
        }
        
        await MainActor.run {
            pendingAction = nil
            showingEditionSheet = false
        }
    }
    
    private func addToWantToRead() async {
        await MainActor.run { isWorking = true }
        
        guard let bookId = book.bookId else {
            await MainActor.run { isWorking = false }
            return
        }
        
        let success = await HardcoverService.addBookToWantToRead(bookId: bookId, editionId: selectedEditionId)
        
        await MainActor.run {
            isWorking = false
            if success {
                onAddComplete(true)
                dismiss()
            }
        }
    }
    
    private func startReading() async {
        await MainActor.run { isWorkingReading = true }
        
        guard let bookId = book.bookId else {
            await MainActor.run { isWorkingReading = false }
            return
        }
        
        let success = await HardcoverService.startReadingBook(bookId: bookId, editionId: selectedEditionId)
        
        await MainActor.run {
            isWorkingReading = false
            if success {
                onAddComplete(true)
                dismiss()
            }
        }
    }
    
    private func markAsFinished() async {
        await MainActor.run { isWorkingFinished = true }
        
        guard let bookId = book.bookId else {
            await MainActor.run { isWorkingFinished = false }
            return
        }
        
        let success = await HardcoverService.finishBookByBookId(
            bookId: bookId,
            editionId: selectedEditionId,
            pages: nil,
            rating: nil
        )
        
        await MainActor.run {
            isWorkingFinished = false
            if success {
                onAddComplete(true)
                dismiss()
            }
        }
    }
    
    private func createUserBookEntry() async {
        await MainActor.run { isCreatingUserBook = true }
        
        guard let bookId = book.bookId else {
            await MainActor.run { isCreatingUserBook = false }
            return
        }
        
        let success = await HardcoverService.finishBookByBookId(
            bookId: bookId,
            editionId: selectedEditionId,
            pages: nil,
            rating: nil
        )
        
        if success {
            let newUserBookId = await fetchLatestUserBookIdForBook(bookId: bookId)
            await MainActor.run {
                isCreatingUserBook = false
                if let newUserBookId = newUserBookId {
                    ratingSheetUserBookId = newUserBookId
                    showingRatingSheet = true
                }
            }
        } else {
            await MainActor.run { isCreatingUserBook = false }
        }
    }
    
    private func loadGenres() async {
        await MainActor.run { isLoadingGenres = true }
        
        guard let bookId = book.bookId,
              let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            await MainActor.run { isLoadingGenres = false }
            return
        }
        
        let fetchedGenres = await queryBookCachedGenres(url: url, bookId: bookId)
        
        await MainActor.run {
            isLoadingGenres = false
            genres = fetchedGenres ?? []
        }
    }
    
    private func loadMoods() async {
        await MainActor.run { isLoadingMoods = true }
        
        guard let bookId = book.bookId,
              let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            await MainActor.run { isLoadingMoods = false }
            return
        }
        
        let fetchedMoods = await queryBookCachedMoods(url: url, bookId: bookId)
        
        await MainActor.run {
            isLoadingMoods = false
            moods = fetchedMoods ?? []
        }
    }
    
    private func loadBookDescription() async {
        // Skip if already have description
        guard book.bookDescription == nil || book.bookDescription?.isEmpty == true else {
            return
        }
        
        await MainActor.run { isLoadingDescription = true }
        
        guard let bookId = book.bookId,
              let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            await MainActor.run { isLoadingDescription = false }
            return
        }
        
        let fetchedDescription = await queryBookDescription(url: url, bookId: bookId)
        
        await MainActor.run {
            isLoadingDescription = false
            bookDescription = fetchedDescription
        }
    }
    
    private func loadReviews() async {
        await loadReviewsPage(page: 0)
    }
    
    private func loadMoreReviews() async {
        guard canLoadMoreReviews else { return }
        await loadReviewsPage(page: reviewsPage + 1)
    }
    
    private func loadReviewsPage(page: Int) async {
        guard let bookId = book.bookId else { return }
        
        await MainActor.run { isLoadingReviews = true }
        
        // Use the available API: limit + offset (offset = page * limit)
        let newReviews = await HardcoverService.fetchPublicReviewsForBook(
            bookId: bookId,
            limit: reviewsPageSize,
            offset: page * reviewsPageSize
        )
        
        await MainActor.run {
            isLoadingReviews = false
            
            if page == 0 {
                reviews = newReviews
            } else {
                reviews.append(contentsOf: newReviews)
            }
            reviewsPage = page
            canLoadMoreReviews = newReviews.count == reviewsPageSize
            reviewsError = nil
        }
    }
    
    private func normalizedDescription(_ desc: String?) -> String? {
        guard let desc = desc?.trimmingCharacters(in: .whitespacesAndNewlines),
              !desc.isEmpty else { return nil }
        return desc
    }
    
    private func loadFinishedStatus() async {
        await MainActor.run { isLoadingFinishedStatus = true }
        
        guard let bookId = book.bookId else {
            await MainActor.run { isLoadingFinishedStatus = false }
            return
        }
        
        let metadataService = BookMetadataService()
        let finishedDatesDict = await metadataService.fetchFinishedBooksWithDates(for: [bookId])
        
        // Fallback: if no date found, still check finished IDs and show as read without date
        var finishedFlag = finishedDatesDict[bookId] != nil
        var dateValue = finishedDatesDict[bookId]
        if !finishedFlag {
            let finishedIds = await metadataService.fetchFinishedBookIds(for: [bookId])
            if finishedIds.contains(bookId) {
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
    
    private func fetchLatestUserBookIdForBook(bookId: Int) async -> Int? {
        // Implementation for fetching user book ID
        return nil
    }
    
    // MARK: - Local GraphQL helpers for cached_tags (genres/moods)
    private func queryBookCachedGenres(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            cached_tags
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
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
                return BookTagExtractor.extractGenres(fromCachedTags: first["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    private func queryBookCachedMoods(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            cached_tags
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
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
                return BookTagExtractor.extractMoods(fromCachedTags: first["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    private func queryBookDescription(url: URL, bookId: Int) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            description
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
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
               let first = books.first,
               let description = first["description"] as? String {
                return description
            }
        } catch { return nil }
        return nil
    }
}

// MARK: - Minimal BookRatingSheet (restores missing symbol)
private struct BookRatingSheet: View {
    let userBookId: Int
    let onDismiss: () -> Void
    
    @State private var rating: Double = 0.0
    @State private var isSaving = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(NSLocalizedString("Rate this book", comment: "Rating sheet title"))
                    .font(.headline)
                
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        let threshold = Double(i) + 1.0
                        Image(systemName: rating >= threshold ? "star.fill" : (rating + 0.5 >= threshold ? "star.leadinghalf.filled" : "star"))
                            .foregroundColor(.orange)
                            .font(.title2)
                            .onTapGesture {
                                rating = threshold
                            }
                    }
                }
                .accessibilityLabel(Text(String(format: NSLocalizedString("Current rating: %.1f of 5", comment: ""), rating)))
                
                VStack {
                    Slider(value: $rating, in: 0...5, step: 0.5)
                    Text(String(format: NSLocalizedString("Rating: %.1f", comment: ""), rating))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("Rate", comment: "Rate navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(NSLocalizedString("Save", comment: "Save button"))
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
    
    private func save() async {
        await MainActor.run { isSaving = true }
        // Update the user book with the selected rating; keep status as "finished" (3) consistent with other calls
        let ok = await HardcoverService.updateUserBook(userBookId: userBookId, statusId: 3, rating: rating)
        await MainActor.run {
            isSaving = false
            onDismiss()
            // Optional: handle failure UI if needed
            _ = ok
        }
    }
}
