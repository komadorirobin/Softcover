import SwiftUI

// MARK: - Feed Filter

enum FeedFilter: String, CaseIterable {
    case yourFeed = "Your Feed"
    case allActivity = "All Activity"
}

// MARK: - FeedView

struct FeedView: View {
    @State private var selectedFilter: FeedFilter = .yourFeed
    @State private var activities: [FeedActivity] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var canLoadMore = true
    
    @State private var selectedBookForDetails: BookProgress?
    @State private var fetchingDetailsForBookId: Int?
    
    private let pageSize = 20
    
    var body: some View {
        VStack(spacing: 0) {
            // Segmented Control
            Picker("Filter", selection: $selectedFilter) {
                ForEach(FeedFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedFilter) { _, _ in
                Task { await reload() }
            }
            
            // Content
            Group {
                if isLoading && activities.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading feed…")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, activities.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Failed to load feed")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await reload() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                } else if activities.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text(selectedFilter == .yourFeed
                             ? "No activity from people you follow"
                             : "No activity found")
                            .font(.headline)
                        if selectedFilter == .yourFeed {
                            Text("Follow other users to see their activity here")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(activities) { activity in
                                FeedActivityCard(
                                    activity: activity,
                                    isFetchingDetails: fetchingDetailsForBookId == activity.bookId,
                                    onBookTap: {
                                        if let bookId = activity.bookId {
                                            Task { await openBookDetails(bookId: bookId, activity: activity) }
                                        }
                                    }
                                )
                                
                                Divider()
                                    .padding(.horizontal)
                                
                                // Infinite scroll trigger
                                if activity.id == activities.last?.id && canLoadMore {
                                    HStack {
                                        Spacer()
                                        if isLoadingMore {
                                            ProgressView()
                                                .padding()
                                        }
                                        Spacer()
                                    }
                                    .onAppear {
                                        Task { await loadMore() }
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await reload()
                    }
                }
            }
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await reload()
        }
        .sheet(item: $selectedBookForDetails) { book in
            NavigationStack {
                BookDetailView(book: book, showFinishAction: false, allowStandaloneReviewButton: true, isOwnBook: false)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func reload() async {
        isLoading = true
        errorMessage = nil
        canLoadMore = true
        
        let fetched: [FeedActivity]
        switch selectedFilter {
        case .yourFeed:
            fetched = await HardcoverService.fetchFeed(offset: 0, limit: pageSize)
        case .allActivity:
            fetched = await HardcoverService.fetchAllActivity(offset: 0, limit: pageSize)
        }
        
        await MainActor.run {
            activities = fetched
            isLoading = false
            canLoadMore = fetched.count >= pageSize
            if fetched.isEmpty && selectedFilter == .yourFeed {
                // Not necessarily an error
                errorMessage = nil
            }
        }
    }
    
    private func loadMore() async {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        
        let offset = activities.count
        let fetched: [FeedActivity]
        switch selectedFilter {
        case .yourFeed:
            fetched = await HardcoverService.fetchFeed(offset: offset, limit: pageSize)
        case .allActivity:
            fetched = await HardcoverService.fetchAllActivity(offset: offset, limit: pageSize)
        }
        
        await MainActor.run {
            // Deduplicate
            let existingIds = Set(activities.map { $0.id })
            let newActivities = fetched.filter { !existingIds.contains($0.id) }
            activities.append(contentsOf: newActivities)
            isLoadingMore = false
            canLoadMore = fetched.count >= pageSize
        }
    }
    
    private func openBookDetails(bookId: Int, activity: FeedActivity) async {
        fetchingDetailsForBookId = bookId
        let bookProgress = BookProgress(
            id: "\(bookId)",
            title: activity.bookTitle ?? "Unknown Book",
            author: activity.authorName ?? "Unknown Author",
            coverImageData: nil,
            coverImageUrl: activity.bookImageURL,
            progress: 0.0,
            totalPages: 0,
            currentPage: 0,
            bookId: bookId,
            userBookId: nil,
            editionId: nil,
            originalTitle: activity.bookTitle ?? "Unknown Book",
            editionAverageRating: nil,
            userRating: nil,
            bookDescription: nil
        )
        await MainActor.run {
            fetchingDetailsForBookId = nil
            selectedBookForDetails = bookProgress
        }
    }
}

// MARK: - Feed Activity Card

struct FeedActivityCard: View {
    let activity: FeedActivity
    let isFetchingDetails: Bool
    let onBookTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User header
            HStack(spacing: 10) {
                // User avatar
                if let imageUrl = activity.userImageURL, let url = URL(string: imageUrl) {
                    AsyncCachedImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.gray)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("@\(activity.username)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        if let flair = activity.userFlair, !flair.isEmpty {
                            Text(flair)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(flairColor(for: flair))
                                .cornerRadius(8)
                        }
                    }
                    
                    Text(formattedTimeAgo(activity.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action icon
                Image(systemName: activity.actionIcon)
                    .foregroundColor(colorFromName(activity.actionColor))
                    .font(.system(size: 16))
            }
            
            // Action text
            HStack(spacing: 4) {
                Text(activity.actionText.capitalized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Rating stars for reviews
                if let rating = activity.rating, rating > 0 {
                    HStack(spacing: 1) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: Double(star) <= rating ? "star.fill" : 
                                  (Double(star) - 0.5 <= rating ? "star.leadinghalf.filled" : "star"))
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            // Book card (if applicable)
            if activity.bookTitle != nil || activity.bookId != nil {
                Button(action: onBookTap) {
                    HStack(spacing: 12) {
                        // Book cover
                        if let imageUrl = activity.bookImageURL, let url = URL(string: imageUrl) {
                            AsyncCachedImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay(
                                        Image(systemName: "book.closed.fill")
                                            .foregroundColor(.gray.opacity(0.5))
                                    )
                            }
                            .frame(width: 50, height: 72)
                            .cornerRadius(4)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 50, height: 72)
                                .overlay(
                                    Image(systemName: "book.closed.fill")
                                        .foregroundColor(.gray.opacity(0.4))
                                )
                        }
                        
                        // Book info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.bookTitle ?? "Unknown Book")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            
                            if let author = activity.authorName, !author.isEmpty {
                                Text(author)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            // Progress indicator
                            if let progress = activity.progress, progress > 0, progress < 100 {
                                HStack(spacing: 6) {
                                    ProgressView(value: Double(progress) / 100.0)
                                        .frame(width: 60)
                                    Text("\(progress)%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if isFetchingDetails {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            
            // Review text preview
            if let review = activity.reviewText, !review.isEmpty {
                Text(review)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
    }
    
    // MARK: - Helpers
    
    private func flairColor(for flair: String) -> Color {
        let lower = flair.lowercased()
        if lower.contains("supporter") { return .pink }
        if lower.contains("librarian") { return .blue }
        if lower.contains("moderator") { return .green }
        if lower.contains("admin") { return .orange }
        if lower.contains("team") { return .blue }
        return .gray
    }
    
    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
    
    private func formattedTimeAgo(_ dateString: String) -> String {
        // Parse the API date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString)
                ?? ISO8601DateFormatter().date(from: dateString)
                ?? parseFlexibleDate(dateString) else {
            return dateString
        }
        
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter.string(from: date)
        }
    }
    
    private func parseFlexibleDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Try common API formats
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}
