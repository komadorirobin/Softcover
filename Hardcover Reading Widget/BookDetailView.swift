import SwiftUI
import UIKit
import WidgetKit

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    
    let book: BookProgress
    // New: controls whether finish action UI is shown
    let showFinishAction: Bool
    
    @State private var showingEditionPicker = false
    
    // Finish/Rating flow
    @State private var showReviewSheet = false
    @State private var selectedRating: Double? = 5.0
    @State private var reviewText: String = ""
    @State private var isActionWorking = false
    @State private var showActionError = false
    
    // Reviews state
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @State private var reviews: [HardcoverService.PublicReview] = []
    @State private var reviewsPage = 0
    private let reviewsPageSize = 10
    @State private var canLoadMoreReviews = true
    
    init(book: BookProgress, showFinishAction: Bool = true) {
        self.book = book
        self.showFinishAction = showFinishAction
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
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Quick actions
                    if book.userBookId != nil {
                        HStack(spacing: 12) {
                            Button {
                                showingEditionPicker = true
                            } label: {
                                Label("Change Edition", systemImage: "books.vertical.fill")
                            }
                            .buttonStyle(.bordered)
                            
                            // Visa INTE "Rate"-knappen i "Läser just nu"-vyn (showFinishAction == true)
                            // Visa den endast när showFinishAction == false (t.ex. historik/andra sammanhang)
                            if !showFinishAction {
                                Button {
                                    selectedRating = book.userRating ?? 5.0
                                    reviewText = ""
                                    showReviewSheet = true
                                } label: {
                                    Label("Rate", systemImage: "star.fill")
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                .disabled(isActionWorking)
                                .accessibilityLabel("Rate this book")
                            }
                            
                            // Mark as finished endast om aktiverad
                            if showFinishAction {
                                Button {
                                    selectedRating = 5.0
                                    reviewText = ""
                                    showReviewSheet = true
                                } label: {
                                    Label("Mark as finished", systemImage: "checkmark.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(isActionWorking)
                                .accessibilityLabel("Mark as finished")
                            }
                        }
                    }
                    
                    // Progress summary – visas endast när showFinishAction är true
                    if showProgressSection {
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
                            
                            // Pages left
                            if let left = pagesLeftText {
                                Text(left)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Progress bar
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
                    
                    // Average rating (edition)
                    if let avg = book.editionAverageRating {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                ReadOnlyStars(rating: avg)
                                Text(String(format: NSLocalizedString("Average %.1f", comment: ""), avg))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Your rating
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
                    
                    // Description
                    if let desc = normalizedDescription(book.bookDescription) {
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
                    }
                    
                    // Reviews section
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
                                        ReviewRow(review: r)
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
                    
                    // Metadata
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
            }
            // Review sheet: används för två flöden
            // - showFinishAction == true: markera som färdig + ev. betyg + recension
            // - showFinishAction == false: uppdatera endast betyg (ingen recension)
            .sheet(isPresented: $showReviewSheet) {
                if showFinishAction {
                    // Full review sheet when finishing book
                    BookReviewSheet(
                        title: NSLocalizedString("How did you like this book?", comment: "Title for review prompt when finishing a book"),
                        subtitle: NSLocalizedString("Rate and review this book to help other readers discover great books!", comment: "Subtitle explaining review when finishing a book"),
                        rating: $selectedRating,
                        reviewText: $reviewText,
                        onSkip: {
                            showReviewSheet = false
                            if let userBookId = book.userBookId {
                                Task {
                                    // Skip rating and review, just mark as finished
                                    await markAsFinished(userBookId: userBookId, rating: nil, reviewText: nil)
                                }
                            }
                        },
                        onConfirm: {
                            let rating = selectedRating ?? 5.0
                            let clamped = max(0.5, min(5.0, (round(rating * 2) / 2)))
                            let review = reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reviewText
                            showReviewSheet = false
                            if let userBookId = book.userBookId {
                                Task {
                                    await markAsFinished(userBookId: userBookId, rating: clamped, reviewText: review)
                                }
                            }
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                } else {
                    // Simple rating sheet for rating-only flow
                    LocalRatingSheet(
                        title: NSLocalizedString("Rate this book", comment: "Title for rating-only prompt"),
                        subtitle: NSLocalizedString("Set your rating for this book. You can change it later.", comment: "Subtitle for rating-only flow"),
                        rating: $selectedRating,
                        onSkip: {
                            showReviewSheet = false
                        },
                        onConfirm: {
                            let raw = selectedRating ?? 5.0
                            let clamped = max(0.5, min(5.0, (round(raw * 2) / 2)))
                            showReviewSheet = false
                            if let userBookId = book.userBookId {
                                Task {
                                    await submitRating(userBookId: userBookId, rating: clamped)
                                }
                            }
                        }
                    )
                    .presentationDetents([.height(300), .medium])
                }
            }
            .alert("Action failed", isPresented: $showActionError) {
                Button("OK") { }
            } message: {
                Text("Please try again.")
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
        if let data = book.coverImageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 90, height: 130)
                .clipped()
                .cornerRadius(8)
                .shadow(radius: 3)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.tertiarySystemFill))
                .frame(width: 90, height: 130)
                .overlay(
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundColor(.secondary)
                )
        }
    }
    
    private func markAsFinished(userBookId: Int, rating: Double?, reviewText: String?) async {
        guard showFinishAction else { return } // Safety: do nothing if disabled
        guard !isActionWorking else { return }
        isActionWorking = true
        let ok = await HardcoverService.finishBook(
            userBookId: userBookId,
            editionId: book.editionId,
            totalPages: book.totalPages > 0 ? book.totalPages : nil,
            currentPage: book.currentPage > 0 ? book.currentPage : nil,
            rating: rating,
            reviewText: reviewText
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
    
    private func submitRating(userBookId: Int, rating: Double?) async {
        guard !isActionWorking else { return }
        isActionWorking = true
        let ok = await HardcoverService.updateUserBookRating(userBookId: userBookId, rating: rating)
        await MainActor.run {
            isActionWorking = false
            if ok {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                WidgetCenter.shared.reloadAllTimelines()
                // Stäng vyn efter lyckad betygsättning
                dismiss()
            } else {
                showActionError = true
            }
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
                                    .foregroundColor(.orange.opacity(0.35))
                            }
                        }
                } else {
                    Image(systemName: "star")
                        .foregroundColor(.orange.opacity(0.35))
                }
            }
        }
        .font(.caption)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating, specifier: "%.1f") of 5")
    }
}

// Lokal rating-sheet (separat från ContentViews privata RatingSheet)
private struct LocalRatingSheet: View {
    let title: String
    let subtitle: String
    @Binding var rating: Double?
    let onSkip: () -> Void
    let onConfirm: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
            
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            LocalStarRatingView(rating: Binding(
                get: { rating ?? 0 },
                set: { rating = $0 }
            ))
            .padding(.horizontal)
            
            VStack(spacing: 6) {
                HStack {
                    Text("Rating: \(rating ?? 0, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Slider(
                    value: Binding(
                        get: { rating ?? 0 },
                        set: { rating = round($0 * 2) / 2 }
                    ),
                    in: 0...5,
                    step: 0.5
                )
                .tint(.orange)
            }
            .padding(.horizontal)
            
            HStack {
                Button("Skip") { onSkip() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Confirm") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled((rating ?? 0) < 0.5)
            }
            .padding(.horizontal)
            
            Spacer(minLength: 8)
        }
        .presentationDragIndicator(.visible)
    }
}

private struct LocalStarRatingView: View {
    @Binding var rating: Double // 0.0–5.0, 0.5 steps
    private let maxRating: Double = 5.0
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                LocalStarCell(
                    index: index,
                    currentRating: rating,
                    onChange: { newValue in
                        rating = max(0, min(maxRating, (round(newValue * 2) / 2)))
                    }
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating, specifier: "%.1f") of \(Int(maxRating))")
        .accessibilityAdjustableAction { direction in
            let step = 0.5
            switch direction {
            case .increment: rating = min(maxRating, rating + step)
            case .decrement: rating = max(0, rating - step)
            @unknown default: break
            }
        }
    }
}

private struct LocalStarCell: View {
    let index: Int
    let currentRating: Double
    let onChange: (Double) -> Void
    
    var body: some View {
        GeometryReader { geo in
            let starIndex = Double(index) + 1.0
            let fillAmount: Double = {
                if currentRating >= starIndex { return 1.0 }
                if currentRating + 0.5 >= starIndex { return 0.5 }
                return 0.0
            }()
            ZStack {
                Image(systemName: "star")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.orange.opacity(0.35))
                if fillAmount >= 1.0 {
                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.orange)
                } else if fillAmount >= 0.5 {
                    if UIImage(systemName: "star.leadinghalf.filled") != nil {
                        Image(systemName: "star.leadinghalf.filled")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "star.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.orange)
                            .mask(
                                Rectangle()
                                    .frame(width: geo.size.width / 2, height: geo.size.height)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let localX = max(0, min(value.location.x, geo.size.width))
                        let half = localX < geo.size.width / 2 ? 0.5 : 1.0
                        let newRating = Double(index) + half
                        onChange(newRating)
                    }
                    .onEnded { value in
                        let localX = max(0, min(value.location.x, geo.size.width))
                        let half = localX < geo.size.width / 2 ? 0.5 : 1.0
                        let newRating = Double(index) + half
                        onChange(newRating)
                    }
            )
        }
        .frame(width: 34, height: 34)
    }
}

// Review row
private struct ReviewRow: View {
    let review: HardcoverService.PublicReview
    
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
                ReadOnlyStars(rating: r)
            }
            if let text = review.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

#Preview {
    let sample = BookProgress(
        id: "1",
        title: "Sample Edition Title",
        author: "Jane Doe",
        coverImageData: nil,
        progress: 0.4,
        totalPages: 320,
        currentPage: 128,
        bookId: 42,
        userBookId: 1001,
        editionId: 777,
        originalTitle: "Sample Original Title",
        editionAverageRating: 4.2,
        userRating: 4.5,
        bookDescription: "This is a sample description of the book. It can span multiple lines and include details about the plot, characters, and themes."
    )
    // Förhandsvisning med showFinishAction=false – här visas "Rate"-knappen.
    return BookDetailView(book: sample, showFinishAction: false)
}
