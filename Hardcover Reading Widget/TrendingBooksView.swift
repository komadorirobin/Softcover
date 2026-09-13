import SwiftUI

struct TrendingBooksView: View {
    @StateObject private var store = ExploreLoadState<HardcoverService.TrendingBook>()
    @State private var selectedFilter: TimeFilter = .lastMonth
    @State private var selectedBook: BookProgress?
    @State private var adding: Set<Int> = []
    @State private var added: Set<Int> = []
    @State private var actionError: String?
    var isActive = true
    let onDone: (Bool) -> Void

    enum TimeFilter: String, CaseIterable {
        case lastMonth = "Last Month"
        case threeMonths = "3 Months"
        case oneYear = "1 Year"
        case allTime = "All Time"
        var path: String {
            switch self {
            case .lastMonth: return "month"
            case .threeMonths: return "recent"
            case .oneYear: return "year"
            case .allTime: return "all"
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Picker("Time Range", selection: $selectedFilter) {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Text(LocalizedStringKey(filter.rawValue)).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal)
                ExploreLoadFeedback(isLoading: store.isLoading, error: store.error ?? actionError,
                                    isEmpty: store.items.isEmpty, emptyTitle: "No trending books found") {
                    Task { await load(refresh: true) }
                }
                ForEach(store.items) { item in
                    BookRow(book: progress(for: item),
                            subtitle: item.usersCount > 0 ? String.localizedStringWithFormat(NSLocalizedString("%lld reading", comment: ""), item.usersCount) : nil,
                            isWorking: adding.contains(item.id),
                            actionIcon: added.contains(item.id) ? "checkmark.circle.fill" : "plus.circle",
                            actionLabel: added.contains(item.id) ? "Added" : "Want to Read",
                            onAction: { if !added.contains(item.id) { Task { await add(item) } } },
                            onOpen: { selectedBook = progress(for: item) })
                        .padding(.horizontal)
                    Divider().padding(.leading, 88)
                }
            }
        }
        .refreshable { await load(refresh: true) }
        .task(id: isActive ? selectedFilter.path : nil) { if isActive { await load() } }
        .navigationDestination(isPresented: Binding(get: { selectedBook != nil }, set: { if !$0 { selectedBook = nil } })) {
            if let selectedBook { BookDetailView(book: selectedBook, isOwnBook: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hardcoverAccountDidChange)) { _ in
            store.reset(); added = []; adding = []
            if isActive { Task { await load() } }
        }
    }

    @MainActor private func load(refresh: Bool = false) async {
        let filter = selectedFilter.path
        actionError = nil
        await store.load(key: filter, refresh: refresh) {
            try await HardcoverReadScope.checked { await HardcoverService.fetchTrendingBooks(timeFilter: filter) }
        }
    }

    private func progress(for item: HardcoverService.TrendingBook) -> BookProgress {
        BookProgress(id: "\(item.id)", title: item.title, author: item.author,
                     coverImageData: nil, coverImageUrl: item.coverImageUrl, progress: 0,
                     totalPages: 0, currentPage: 0, bookId: item.id, userBookId: nil, editionId: nil, originalTitle: item.title)
    }

    @MainActor private func add(_ item: HardcoverService.TrendingBook) async {
        guard !adding.contains(item.id), !added.contains(item.id) else { return }
        let account = HardcoverConfig.authorizationHeaderValue
        adding.insert(item.id)
        defer { adding.remove(item.id) }
        let success = await HardcoverService.addBookToWantToRead(bookId: item.id, editionId: nil)
        guard !Task.isCancelled, account == HardcoverConfig.authorizationHeaderValue else { return }
        if success {
            added.insert(item.id)
            onDone(true)
        } else { actionError = NSLocalizedString("Could not add book", comment: "") }
    }
}
