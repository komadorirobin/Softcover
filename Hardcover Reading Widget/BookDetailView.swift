// (endast relevant ändring: loadFinishedStatus fallback till finished IDs)
import SwiftUI
import UIKit
import WidgetKit
import Foundation

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    
    let book: BookProgress
    // New: controls whether finish action UI is shown
    let showFinishAction: Bool
    // NEW: controls if the standalone "Omdöme" button is shown when showFinishAction is false
    let allowStandaloneReviewButton: Bool
    
    @State private var showingEditionPicker = false
    
    // Finish/Rating/Review flow
    @State private var showRatingSheet = false
    @State private var selectedRating: Double? = nil
    @State private var isActionWorking = false
    @State private var showActionError = false
    @State private var showStatusChangeMenu = false
    @State private var showReadingDates = false
    
    // Reviews state
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @State private var reviews: [HardcoverService.PublicReview] = []
    @State private var reviewsPage = 0
    private let reviewsPageSize = 10
    @State private var canLoadMoreReviews = true
    
    // Genres & Moods state
    @State private var genres: [String] = []
    @State private var isLoadingGenres = false
    @State private var moods: [String] = []
    @State private var isLoadingMoods = false
    
    // Description state (fallback fetch if missing)
    @State private var descriptionText: String?
    @State private var isLoadingDescription = false
    
    // Average rating (book-level fallback if edition rating is missing)
    @State private var averageRating: Double?
    
    // Read status state (to show "Läst (datum)" if already finished)
    @State private var isFinished = false
    @State private var finishedDate: Date?
    @State private var isLoadingFinishedStatus = false
    
    init(book: BookProgress, showFinishAction: Bool = true, allowStandaloneReviewButton: Bool = true) {
        self.book = book
        self.showFinishAction = showFinishAction
        self.allowStandaloneReviewButton = allowStandaloneReviewButton
    }
    
    private var percentText: String? {
        guard book.progress > 0 else { return nil }
        return "\(Int(book.progress * 100))%"
    }
    
    private var pagesLeftText: String? {
        guard book.totalPages > 0 else { return nil }
        let left = max(0, book.totalPages - max(0, book.currentPage))
        return left > 0 ? String(format: NSLocalizedString("%d pages left", comment: ""), left) : NSLocalizedString("No pages left", comment: "")
    }
    
    // Visa progress-sektionen endast när finish-åtgärden är aktiv (dvs. inte från historikvyn)
    private var showProgressSection: Bool {
        return showFinishAction
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    
                    if isFinished {
                        VStack(spacing: 12) {
                            BookReadStatusView(finishedDate: finishedDate)
                        }
                        
                        // Status change buttons for read books
                        if let userBookId = book.userBookId {
                            HStack(spacing: 12) {
                                Button {
                                    Task { await changeStatusToReading(userBookId: userBookId) }
                                } label: {
                                    Label("Mark as Reading", systemImage: "book.fill")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isActionWorking)
                                
                                Button {
                                    Task { await changeStatusToWantToRead(userBookId: userBookId) }
                                } label: {
                                    Label("Want to Read", systemImage: "bookmark.fill")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isActionWorking)
                            }
                        }
                    }
                    
                    // Show "Dates Read" button for any book in user's library
                    if let userBookId = book.userBookId {
                        Button {
                            showReadingDates = true
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                Text("Dates Read")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    quickActionsSection
                    
                    if showProgressSection {
                        progressSection
                    }
                    
                    yourRatingSection
                    
                    descriptionSection
                    
                    reviewsSection
                    
                    metadataSection
                    
                    Spacer(minLength: 8)
                }
                .padding()
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                // Keep "Change edition" in toolbar if applicable
                if book.userBookId != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingEditionPicker = true
                        } label: {
                            Image(systemName: "books.vertical.fill")
                        }
                        .accessibilityLabel("Change Edition")
                    }
                }
            }
            .background(Color(UIColor.systemBackground))
            .sheet(isPresented: $showingEditionPicker) {
                EditionPickerView(book: book) { success in
                    if success {
                        WidgetCenter.shared.reloadAllTimelines()
                        print("✅ Widget timelines reloaded after edition change from BookDetailView.")
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            // Sheet-hantering:
            // - showFinishAction == true: Finish+Rate+Review -> markerar färdig
            // - showFinishAction == false: Omdöme -> spara betyg (om ändrat) + publicera recension, men INTE markera som färdig
            .sheet(isPresented: $showRatingSheet) {
                if let userBookId = book.userBookId {
                    if showFinishAction {
                        FinishRateReviewSheet(
                            userBookId: userBookId,
                            initialRating: selectedRating,
                            onPublishedReview: {},
                            onSkip: { rating in
                                Task { await markAsFinished(userBookId: userBookId, rating: rating) }
                            },
                            onConfirmFinish: { rating in
                                Task { await markAsFinished(userBookId: userBookId, rating: rating) }
                            }
                        )
                        .presentationDetents([.large, .medium])
                    } else {
                        // Kombinerat ark för historik: publicera recension och spara betyg om ändrat, men avsluta inte boken.
                        FinishRateReviewSheet(
                            userBookId: userBookId,
                            initialRating: selectedRating,
                            onPublishedReview: {
                                // valfritt: feedback
                            },
                            onSkip: { rating in
                                // Om användaren ändrade betyg och tryckte "Skip", spara bara betyget.
                                Task { _ = await HardcoverService.updateUserBook(userBookId: userBookId, statusId: 3, rating: rating) }
                            },
                            onConfirmFinish: { rating in
                                // Arkets logik publicerar recensionen innan denna kallas.
                                // Här markerar vi INTE som färdig; spara bara betyg om ändrat (säkerhet).
                                Task { _ = await HardcoverService.updateUserBook(userBookId: userBookId, statusId: 3, rating: rating) }
                            }
                        )
                        .presentationDetents([.large, .medium])
                    }
                }
            }
            .alert("Action failed", isPresented: $showActionError) {
                Button("OK") { }
            } message: {
                Text("Please try again.")
            }
            .sheet(isPresented: $showReadingDates) {
                if let userBookId = book.userBookId {
                    ReadingDatesView(userBookId: userBookId, editionId: book.editionId)
                }
            }
            // Ladda genres & moods när vyn visas
            .task { await reloadTaxonomies() }
            // Ladda beskrivning om den saknas i modellen
            .task {
                if descriptionText == nil,
                   (book.bookDescription == nil || book.bookDescription?.isEmpty == true),
                   let id = book.bookId {
                    await MainActor.run { isLoadingDescription = true }
                    let fetched = await fetchBookDescription(bookId: id)
                    await MainActor.run {
                        descriptionText = fetched
                        isLoadingDescription = false
                    }
                }
            }
            // Ladda medelbetyg på boknivå om editionsbetyg saknas
            .task {
                if averageRating == nil, book.editionAverageRating == nil, let id = book.bookId {
                    let avg = await fetchBookAverageRating(bookId: id)
                    await MainActor.run { averageRating = avg }
                }
            }
            // Ladda färdigstatus (för att visa "Läst (datum)")
            .task {
                await loadFinishedStatus()
            }
        }
    }
    
    private var originalTitleText: String? {
        guard !book.originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Only show if different from displayed title
        if book.originalTitle != book.title {
            return String(format: NSLocalizedString("Original title: %@", comment: ""), book.originalTitle)
        }
        return nil
    }
    
    // If description might contain stray HTML tags, strip very basic tags.
    private func normalizedDescription(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        // Lightweight sanitation: remove very simple tags if present.
        let withoutTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return withoutTags.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @ViewBuilder
    private var coverView: some View {
        Group {
            if let data = book.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 90, height: 130)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(radius: 3)
            } else if let urlString = book.coverImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 90, height: 130)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 90, height: 130)
                            .clipped()
                            .cornerRadius(8)
                            .shadow(radius: 3)
                    case .failure:
                        placeholderCover
                    @unknown default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
    }
    
    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(UIColor.tertiarySystemFill))
            .frame(width: 90, height: 130)
            .overlay(
                Image(systemName: "book.closed")
                    .font(.title2)
                    .foregroundColor(.secondary)
            )
    }
    
    private func markAsFinished(userBookId: Int, rating: Double?) async {
        guard showFinishAction else { return } // Safety: do nothing if disabled
        guard !isActionWorking else { return }
        isActionWorking = true
        let ok = await HardcoverService.finishBook(
            userBookId: userBookId,
            editionId: book.editionId,
            totalPages: book.totalPages > 0 ? book.totalPages : nil,
            currentPage: book.currentPage > 0 ? book.currentPage : nil,
            rating: rating // may be nil if untouched
        )
        await MainActor.run {
            isActionWorking = false
            if ok {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                WidgetCenter.shared.reloadAllTimelines()
                // Close after success
                dismiss()
            } else {
                showActionError = true
            }
        }
    }
    
    // MARK: - Finished status loading
    private func loadFinishedStatus() async {
        guard let bookId = book.bookId else { return }
        await MainActor.run { isLoadingFinishedStatus = true }
        let metadataService = BookMetadataService()
        let finishedDates = await metadataService.fetchFinishedBooksWithDates(for: [bookId])
        
        // Fallback: finished utan datum
        var finishedFlag = finishedDates[bookId] != nil
        var dateValue = finishedDates[bookId]
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
    
    // MARK: - Reviews loading
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
    
    // MARK: - Genres & Moods loading
    private func reloadTaxonomies() async {
        // Fetch both in parallel
        await MainActor.run {
            isLoadingGenres = genres.isEmpty
            isLoadingMoods = moods.isEmpty
        }
        async let g = fetchGenresPreferred(bookId: book.bookId, editionId: book.editionId, userBookId: book.userBookId)
        async let m = fetchMoodsPreferred(bookId: book.bookId, editionId: book.editionId, userBookId: book.userBookId)
        let (gList, mList) = await (g, m)
        await MainActor.run {
            self.genres = gList
            self.moods = mList
            self.isLoadingGenres = false
            self.isLoadingMoods = false
        }
    }
    
    // MARK: - UI Sections (split to help the compiler)
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            coverView
            
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                if let original = originalTitleText {
                    Text(original)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if let avg = (book.editionAverageRating ?? averageRating) {
                    HStack(spacing: 8) {
                        ReadOnlyStars(rating: avg)
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
                    Divider()
                        .padding(.vertical, 2)
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
    }
    
    @ViewBuilder
    private var quickActionsSection: some View {
        if book.userBookId != nil {
            HStack(spacing: 12) {
                Button {
                    showingEditionPicker = true
                } label: {
                    Label("Change Edition", systemImage: "books.vertical.fill")
                }
                .buttonStyle(.bordered)
                
                if !showFinishAction && allowStandaloneReviewButton {
                    Button {
                        selectedRating = book.userRating
                        showRatingSheet = true
                    } label: {
                        Label(NSLocalizedString("Omdöme", comment: "Rate & Review combined action"), systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isActionWorking)
                    .accessibilityLabel(NSLocalizedString("Betyg & omdöme", comment: "Accessibility label for combined rate & review"))
                }
                
                if showFinishAction {
                    Button {
                        selectedRating = book.userRating
                        showRatingSheet = true
                    } label: {
                        Label("Mark as finished", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isActionWorking)
                    .accessibilityLabel("Mark as finished")
                }
            }
        } else if let bookId = book.bookId {
            // Book not in user's library yet - show "Start Reading" and "Want to Read" buttons
            HStack(spacing: 12) {
                Button {
                    Task { await startReading(bookId: bookId) }
                } label: {
                    Label("Start Reading", systemImage: "book.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActionWorking)
                
                Button {
                    Task { await addToWantToRead(bookId: bookId) }
                } label: {
                    Label("Want to Read", systemImage: "bookmark.fill")
                }
                .buttonStyle(.bordered)
                .disabled(isActionWorking)
            }
        }
    }
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if book.totalPages > 0 && book.currentPage > 0 {
                    Text("Page \(book.currentPage) of \(book.totalPages)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if book.currentPage > 0 {
                    Text("Page \(book.currentPage)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if book.totalPages > 0 {
                    Text("\(book.totalPages) pages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No progress information")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let pct = percentText {
                    Text(pct)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }
            
            if let left = pagesLeftText {
                Text(left)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.25))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: CGFloat(book.progress) * geometry.size.width)
                }
            }
            .frame(height: 8)
        }
    }
    
    @ViewBuilder
    private var yourRatingSection: some View {
        if let my = book.userRating {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ReadOnlyStars(rating: my)
                    Text(String(format: NSLocalizedString("Your rating: %.1f", comment: ""), my))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var descriptionSection: some View {
        if let desc = normalizedDescription(descriptionText ?? book.bookDescription) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                Text(desc)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        } else if isLoadingDescription {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.9)
                Text(NSLocalizedString("Loading description…", comment: "Loading state for description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private var reviewsSection: some View {
        if let bookId = book.bookId {
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
                            // Use the shared row from SearchDetailComponents.swift
                            SearchReviewRow(review: r)
                        }
                        if canLoadMoreReviews {
                            HStack {
                                Spacer()
                                Button {
                                    Task { await loadMoreReviews(for: bookId) }
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
            .task {
                // Initial load once when the view appears
                if reviewsPage == 0 && reviews.isEmpty {
                    await reloadReviews(for: bookId)
                }
            }
        }
    }
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eid = book.editionId {
                Label("Edition ID: \(eid)", systemImage: "books.vertical.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let bid = book.bookId {
                Label("Book ID: \(bid)", systemImage: "number")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let uid = book.userBookId {
                Label("User Book ID: \(uid)", systemImage: "person.text.rectangle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - GraphQL helpers (local copies to satisfy symbols)
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
        } catch { return nil }
        return nil
    }
    
    private func fetchBookDescription(bookId: Int) async -> String? {
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
            description
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
                return first["description"] as? String
            }
        } catch { return nil }
        return nil
    }
    
    private func fetchGenresPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        // Curated-only (cached_tags) for genres, prefer book -> userBook paths
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
        // Taggings first, then cached_tags, across book/edition/user_book
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
    
    private func startReading(bookId: Int) async {
        guard !isActionWorking else { return }
        await MainActor.run { isActionWorking = true }
        
        let result = await HardcoverService.startReadingBook(bookId: bookId, editionId: book.editionId)
        
        await MainActor.run {
            isActionWorking = false
            if result {
                // Refresh widget
                WidgetCenter.shared.reloadAllTimelines()
                // Close the view since book is now added
                dismiss()
            } else {
                showActionError = true
            }
        }
    }
    
    private func addToWantToRead(bookId: Int) async {
        guard !isActionWorking else { return }
        await MainActor.run { isActionWorking = true }
        
        let result = await HardcoverService.addBookToWantToRead(bookId: bookId, editionId: book.editionId)
        
        await MainActor.run {
            isActionWorking = false
            if result {
                // Refresh widget
                WidgetCenter.shared.reloadAllTimelines()
                // Close the view since book is now added
                dismiss()
            } else {
                showActionError = true
            }
        }
    }
    
    // Change status from Read to Reading (preserves read dates)
    private func changeStatusToReading(userBookId: Int) async {
        guard !isActionWorking else { return }
        await MainActor.run { isActionWorking = true }
        
        let today = utcDateString()
        let ok = await HardcoverService.updateUserBookWithDate(
            userBookId: userBookId,
            editionId: book.editionId,
            statusId: 2, // Currently Reading
            rating: book.userRating,
            lastReadDate: today,
            dateAdded: nil,
            userDate: today
        )
        
        await MainActor.run {
            isActionWorking = false
            if ok {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                WidgetCenter.shared.reloadAllTimelines()
                dismiss()
            } else {
                showActionError = true
            }
        }
    }
    
    // Change status from Read to Want to Read (preserves read dates)
    private func changeStatusToWantToRead(userBookId: Int) async {
        guard !isActionWorking else { return }
        await MainActor.run { isActionWorking = true }
        
        let ok = await HardcoverService.updateUserBookWithDate(
            userBookId: userBookId,
            editionId: book.editionId,
            statusId: 1, // Want to Read
            rating: book.userRating,
            lastReadDate: nil,
            dateAdded: nil,
            userDate: nil
        )
        
        await MainActor.run {
            isActionWorking = false
            if ok {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                WidgetCenter.shared.reloadAllTimelines()
                dismiss()
            } else {
                showActionError = true
            }
        }
    }
    
    private func utcDateString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.string(from: Date())
    }
}


