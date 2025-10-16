import SwiftUI
import UIKit

struct HistoryView: View {
    
    // Paginering för normal listvy
    @State private var items: [FinishedBookEntry] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var page = 0
    @State private var canLoadMore = true
    @State private var seenBookIds: Set<Int> = [] // för normal vyladdning
    
    // Full sök-cache (alla sidor)
    @State private var allItems: [FinishedBookEntry] = []
    @State private var isLoadingAllForSearch = false
    @State private var allLoaded = false
    @State private var allSeenBookIds: Set<Int> = [] // separat dedup för full cache
    
    // Detaljer
    @State private var selectedBookForDetails: BookProgress?
    @State private var fetchingDetailsForBookId: Int?
    
    // Totalt antal (för infotext)
    @State private var totalFinishedCount: Int?
    
    // Sök
    @State private var searchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    
    private let pageSize = 25
    
    private var titleText: String {
        NSLocalizedString("Reading History", comment: "Title for reading history view")
    }
    
    // Är sökning aktiv?
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Basdata för filtrering: när vi söker och full cache finns (eller laddas), använd allItems; annars items
    private var searchBase: [FinishedBookEntry] {
        if isSearching {
            return allItems.isEmpty ? items : allItems
        } else {
            return items
        }
    }
    
    // Filtrerade poster
    private var filteredItems: [FinishedBookEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return searchBase.filter { entry in
            entry.title.localizedCaseInsensitiveContains(q) ||
            entry.author.localizedCaseInsensitiveContains(q)
        }
    }
    
    // Info-rad
    private var infoLineText: String? {
        let total = totalFinishedCount ?? (isSearching ? searchBase.count : items.count)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            return String.localizedStringWithFormat(
                NSLocalizedString("Showing %d of %d", comment: "Info line when filtering history: showing N of X total"),
                filteredItems.count,
                total
            )
        } else {
            return String.localizedStringWithFormat(
                NSLocalizedString("%d in History", comment: "Info line above history list: total finished count"),
                total
            )
        }
    }
    
    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.3)
                        Text(NSLocalizedString("Loading history…", comment: "Loading state for reading history"))
                            .foregroundColor(.secondary)
                    }
                } else if let error = errorMessage, items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("Failed to load history", comment: "Error title for reading history load failure"))
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(NSLocalizedString("Try Again", comment: "Retry button")) { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                } else {
                    List {
                        // Info-rad överst
                        if let info = infoLineText {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text(info)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if isSearching && isLoadingAllForSearch {
                                    ProgressView().scaleEffect(0.7)
                                }
                                Spacer(minLength: 0)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                        }
                        
                        // Innehåll
                        if filteredItems.isEmpty && isSearching {
                            // Sökning aktiv men inga träffar (än)
                            if isLoadingAllForSearch && !allLoaded {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 8) {
                                        ProgressView().scaleEffect(0.9)
                                        Text(NSLocalizedString("Searching more of your history…", comment: "Searching more pages for history"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                            } else {
                                VStack(spacing: 8) {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    Text(NSLocalizedString("No matches found", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            }
                        } else {
                            ForEach(filteredItems) { entry in
                                ZStack(alignment: .trailing) {
                                    HistoryRow(entry: entry)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            Task { await openDetails(for: entry) }
                                        }
                                    
                                    if fetchingDetailsForBookId == entry.bookId {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                }
                            }
                        }
                        
                        // Visa "Load More" endast när vi inte söker
                        if !isSearching && canLoadMore {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                        .padding(.vertical, 12)
                                } else {
                                    Button(NSLocalizedString("Load More", comment: "Load more history button")) {
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
                }
            }
            .navigationTitle(titleText)
            .task {
            await loadTotalFinishedCount()
            await initialLoad()
        }
        // Present detail view with finish action hidden (already read)
        .sheet(item: $selectedBookForDetails) { book in
            BookDetailView(book: book, showFinishAction: false)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Avsluta ev. full-laddning och återgå till normal vy
                isLoadingAllForSearch = false
                return
            }
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await ensureAllLoadedForSearch()
            }
        }
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
    
    private func loadTotalFinishedCount() async {
        let stats = await HardcoverService.fetchReadingStats(year: nil)
        await MainActor.run {
            if let stats {
                totalFinishedCount = stats.booksFinished
            }
        }
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
            // Deduplicera per bok (nyast vinner)
            let filtered = fetched.filter { !seenBookIds.contains($0.bookId) }
            for entry in filtered {
                seenBookIds.insert(entry.bookId)
            }
            items.append(contentsOf: filtered)
            page += 1
            
            if filtered.isEmpty && fetched.count < pageSize {
                canLoadMore = false
            }
        }
    }
    
    // Ladda ALLA sidor i en separat cache för sökning (en gång per session)
    private func ensureAllLoadedForSearch() async {
        // Om redan komplett laddat eller pågående, gör inget
        if allLoaded || isLoadingAllForSearch { return }
        
        await MainActor.run {
            isLoadingAllForSearch = true
            // Om du vill rensa och börja om varje gång man börjar söka, avkommentera:
            // allItems = []
            // allSeenBookIds = []
        }
        
        var localPage = 0
        let pageSize = self.pageSize
        
        while true {
            let offset = localPage * pageSize
            let fetched = await HardcoverService.fetchReadingHistory(limit: pageSize, offset: offset)
            if fetched.isEmpty {
                break
            }
            // Dedup i full-cache också (nyast vinner)
            let filtered = fetched.filter { !allSeenBookIds.contains($0.bookId) }
            if !filtered.isEmpty {
                await MainActor.run {
                    for e in filtered { allSeenBookIds.insert(e.bookId) }
                    allItems.append(contentsOf: filtered)
                }
            }
            localPage += 1
            if fetched.count < pageSize {
                // sista sidan
                break
            }
            // Avbryt om användaren slutat söka
            if Task.isCancelled || !isSearching {
                break
            }
        }
        
        await MainActor.run {
            isLoadingAllForSearch = false
            // Om vi nådde sista sidan (eller inga fler), markera som komplett
            if !isSearching || (allItems.count >= (totalFinishedCount ?? allItems.count)) {
                allLoaded = true
            }
        }
    }
    
    private func openDetails(for entry: FinishedBookEntry) async {
        await MainActor.run { fetchingDetailsForBookId = entry.bookId }
        let fetched = await HardcoverService.fetchBookDetailsById(bookId: entry.bookId, userBookId: entry.userBookId)
        await MainActor.run {
            fetchingDetailsForBookId = nil
            if let book = fetched {
                selectedBookForDetails = book
            } else {
                let bp = BookProgress(
                    id: "\(entry.id)",
                    title: entry.title,
                    author: entry.author,
                    coverImageData: entry.coverImageData,
                    progress: 0,
                    totalPages: 0,
                    currentPage: 0,
                    bookId: entry.bookId,
                    userBookId: entry.userBookId,
                    editionId: nil,
                    originalTitle: entry.title,
                    editionAverageRating: nil,
                    userRating: entry.rating,
                    bookDescription: nil
                )
                selectedBookForDetails = bp
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
