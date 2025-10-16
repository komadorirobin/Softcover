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
                    
                    // Quick actions
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
                    if let desc = normalizedDescription(book.bookDescription) {
                        BookDescriptionView(description: desc)
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
            group.addTask { await loadGenres() }
            group.addTask { await loadMoods() }
            group.addTask { await loadReviews() }
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
        
        let result = await HardcoverService.fetchPublicReviews(
            for: bookId,
            page: page,
            limit: reviewsPageSize
        )
        
        await MainActor.run {
            isLoadingReviews = false
            
            switch result {
            case .success(let newReviews):
                if page == 0 {
                    reviews = newReviews
                } else {
                    reviews.append(contentsOf: newReviews)
                }
                reviewsPage = page
                canLoadMoreReviews = newReviews.count == reviewsPageSize
                reviewsError = nil
            case .failure(let error):
                if page == 0 {
                    reviewsError = error.localizedDescription
                }
                canLoadMoreReviews = false
            }
        }
    }
    
    private func normalizedDescription(_ desc: String?) -> String? {
        guard let desc = desc?.trimmingCharacters(in: .whitespacesAndNewlines),
              !desc.isEmpty else { return nil }
        return desc
    }
    
    private func fetchLatestUserBookIdForBook(bookId: Int) async -> Int? {
        // Implementation for fetching user book ID
        return nil
    }
}