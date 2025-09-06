import SwiftUI
import WidgetKit

struct WantToReadView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var items: [BookProgress] = []
    @State private var isLoading = true
    @State private var isWorkingId: String?
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    // NYTT: öppna bokdetaljer
    @State private var selectedBookForDetails: BookProgress?
    
    let onComplete: (Bool) -> Void
    
    init(onComplete: @escaping (Bool) -> Void) {
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading && items.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.3)
                        Text("Loading Want to Read…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        Text("Failed to load list")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No books in Want to Read")
                            .font(.headline)
                        Text("Add books to your Want to Read list on Hardcover to see them here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredItems) { book in
                            HStack(spacing: 12) {
                                cover(for: book)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)
                                    Text(book.author)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    
                                    if book.totalPages > 0 {
                                        Text("\(book.totalPages) pages")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if let id = book.userBookId {
                                    if isWorkingId == book.id {
                                        ProgressView()
                                    } else {
                                        Button {
                                            Task { await startReading(userBookId: id) }
                                        } label: {
                                            Label("Läs nu", systemImage: "book.fill")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .tint(.accentColor) // Byt från grönt till appens accentfärg (lila)
                                        .accessibilityLabel("Läs nu")
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle()) // gör hela raden klickbar för onTapGesture
                            .onTapGesture {
                                selectedBookForDetails = book
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Want to Read")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await reload() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .task { await initialLoad() }
            .refreshable { await reload() }
            .alert("Action failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            // NYTT: presentera bokdetaljer
            .sheet(item: $selectedBookForDetails) { book in
                InlineBookDetailView(book: book) { id in
                    Task { await startReading(userBookId: id) }
                }
            }
        }
    }
    
    private var filteredItems: [BookProgress] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.author.localizedCaseInsensitiveContains(q)
        }
    }
    
    private func cover(for book: BookProgress) -> some View {
        Group {
            if let data = book.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "book.closed")
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(width: 44, height: 64)
        .clipped()
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    
    private func initialLoad() async {
        if items.isEmpty {
            await reload()
        }
    }
    
    private func reload() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        let list = await HardcoverService.fetchWantToRead(limit: 200)
        await MainActor.run {
            items = list
            isLoading = false
        }
    }
    
    private func startReading(userBookId: Int) async {
        guard isWorkingId == nil else { return }
        await MainActor.run { isWorkingId = "\(userBookId)" }
        let ok = await HardcoverService.updateUserBookStatus(userBookId: userBookId, statusId: 2)
        await MainActor.run {
            isWorkingId = nil
            if ok {
                WidgetCenter.shared.reloadAllTimelines()
                onComplete(true)
                dismiss()
            } else {
                errorMessage = "Could not start reading. Please try again."
            }
        }
    }
}

// Lightweight inline detail sheet to avoid cross-target dependency on BookDetailView
private struct InlineBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let book: BookProgress
    let onStart: (Int) -> Void
    
    // Reviews state
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @State private var reviews: [HardcoverService.PublicReview] = []
    @State private var reviewsPage = 0
    private let reviewsPageSize = 10
    @State private var canLoadMoreReviews = true
    
    private var percentText: String? {
        guard book.progress > 0 else { return nil }
        return "\(Int(book.progress * 100))%"
    }
    
    private var pagesInfo: String {
        if book.totalPages > 0 && book.currentPage > 0 {
            return "Page \(book.currentPage) of \(book.totalPages)"
        } else if book.currentPage > 0 {
            return "Page \(book.currentPage)"
        } else if book.totalPages > 0 {
            return "\(book.totalPages) pages"
        } else {
            return "No progress information"
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
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
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .lineLimit(3)
                            
                            Text(book.author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            if book.originalTitle != book.title && !book.originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Original title: \(book.originalTitle)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Snabbåtgärd: Läs nu
                    if let userBookId = book.userBookId {
                        Button {
                            onStart(userBookId)
                        } label: {
                            Label("Läs nu", systemImage: "book.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .accessibilityLabel("Läs nu")
                    }
                    
                    // Progress (utan progress-bar)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(pagesInfo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if let pct = percentText {
                                Text(pct)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    // Average rating (edition)
                    if let avg = book.editionAverageRating {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                InlineReadOnlyStars(rating: avg)
                                Text(String(format: NSLocalizedString("Average %.1f", comment: ""), avg))
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
                    }
                    
                    // Reviews section (NYTT)
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
                                        InlineReviewRow(review: r)
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
                }
                .padding()
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let userBookId = book.userBookId {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            onStart(userBookId)
                        } label: {
                            Image(systemName: "book.fill")
                        }
                        .accessibilityLabel("Läs nu")
                    }
                }
            }
        }
    }
    
    // If description might contain stray HTML tags, strip very basic tags.
    private func normalizedDescription(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let withoutTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return withoutTags.trimmingCharacters(in: .whitespacesAndNewlines)
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

// Enkel read-only stjärnvy för betyg
private struct InlineReadOnlyStars: View {
    let rating: Double // 0…5
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let threshold = Double(i) + 1.0
                if rating >= threshold {
                    Image(systemName: "star.fill")
                        .foregroundColor(.orange)
                } else if rating + 0.5 >= threshold {
                    // Använd SF-symbolen för halva stjärnor (tillgänglig i moderna system)
                    Image(systemName: "star.leadinghalf.filled")
                        .foregroundColor(.orange)
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

// Recensionsrad för inline-detaljvyn
private struct InlineReviewRow: View {
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
                InlineReadOnlyStars(rating: r)
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

