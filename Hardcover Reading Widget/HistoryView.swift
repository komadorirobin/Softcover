import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var items: [FinishedBookEntry] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var page = 0
    @State private var canLoadMore = true
    
    // Track seen bookIds so that only the latest finished read per book is shown
    @State private var seenBookIds: Set<Int> = []
    
    private let pageSize = 25
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading && items.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.3)
                        Text("Loading history…")
                            .foregroundColor(.secondary)
                    }
                } else if let error = errorMessage, items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        Text("Failed to load history")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No finished books yet")
                            .font(.headline)
                        Text("When you finish books on Hardcover, they’ll appear here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(items) { entry in
                            HistoryRow(entry: entry)
                        }
                        
                        if canLoadMore {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                        .padding(.vertical, 12)
                                } else {
                                    Button("Load More") {
                                        Task { await loadMore() }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 12)
                                }
                                Spacer()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Reading History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await initialLoad() }
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
            page = 0
            items = []
            seenBookIds = []
            canLoadMore = true
        }
        await loadPage(reset: true)
    }
    
    private func loadMore() async {
        guard !isLoadingMore, canLoadMore else { return }
        await MainActor.run { isLoadingMore = true }
        await loadPage(reset: false)
        await MainActor.run { isLoadingMore = false }
    }
    
    private func loadPage(reset: Bool) async {
        let offset = page * pageSize
        let fetched = await HardcoverService.fetchReadingHistory(limit: pageSize, offset: offset)
        
        await MainActor.run {
            isLoading = false
            if fetched.isEmpty {
                canLoadMore = false
                return
            }
            // Deduplicate by bookId, keeping only the latest appearance (we’re loading newest-first pages).
            let filtered = fetched.filter { !seenBookIds.contains($0.bookId) }
            for entry in filtered {
                seenBookIds.insert(entry.bookId)
            }
            items.append(contentsOf: filtered)
            page += 1
            
            // If the whole page was filtered out, try allowing further pages
            // to find unseen books; but stop when we start receiving empty pages.
            if filtered.isEmpty && fetched.count < pageSize {
                canLoadMore = false
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: FinishedBookEntry
    
    var body: some View {
        HStack(spacing: 12) {
            if let data = entry.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 64)
                    .clipped()
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 44, height: 64)
                    .overlay(
                        Image(systemName: "book.closed")
                            .foregroundColor(.secondary)
                    )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Text(entry.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    ReadOnlyStarRatingView(rating: entry.rating ?? 0)
                    Spacer()
                    Text(entry.finishedAt, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReadOnlyStarRatingView: View {
    let rating: Double // 0…5 in 0.5 steps
    
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
