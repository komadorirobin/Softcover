import SwiftUI

struct CommunityUpcomingView: View {
    @StateObject private var store = ExploreLoadState<CommunityUpcomingBook>()
    @State private var selectedFilter: TimeFilter = .oneMonth
    @State private var selectedBook: BookProgress?
    var isActive = true

    enum TimeFilter: String, CaseIterable {
        case recent = "Recent"
        case oneMonth = "1 Month"
        case threeMonths = "3 Months"
        case oneYear = "1 Year"
        var path: String {
            switch self {
            case .recent: return "recent"
            case .oneMonth: return "month"
            case .threeMonths: return "quarter"
            case .oneYear: return "year"
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
                ExploreLoadFeedback(isLoading: store.isLoading, error: store.error,
                                    isEmpty: store.items.isEmpty, emptyTitle: "No upcoming releases found") {
                    Task { await load(refresh: true) }
                }
                ForEach(store.items) { book in
                    BookRow(book: book.toBookProgress(), subtitle: book.releaseDate) {
                        selectedBook = book.toBookProgress()
                    }
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
            store.reset()
            if isActive { Task { await load() } }
        }
    }

    @MainActor private func load(refresh: Bool = false) async {
        let filter = selectedFilter.path
        await store.load(key: filter, refresh: refresh) {
            try await HardcoverService.communityUpcomingReleases(filter: filter)
        }
    }
}
