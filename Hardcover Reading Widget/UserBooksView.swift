import SwiftUI

enum UserBookFilter: Int, CaseIterable {
    case wantToRead = 1, currentlyReading = 2, finished = 3
    var title: LocalizedStringKey {
        switch self {
        case .wantToRead: return "Want to Read"
        case .currentlyReading: return "Currently Reading"
        case .finished: return "Finished"
        }
    }
}

struct UserBooksView: View {
    let username: String
    @State private var selectedFilter = UserBookFilter.wantToRead
    @StateObject private var wanted: LibraryListStore
    @StateObject private var reading: LibraryListStore
    @StateObject private var finished: LibraryListStore

    init(username: String) {
        self.username = username
        _wanted = StateObject(wrappedValue: LibraryListStore(status: 1, username: username))
        _reading = StateObject(wrappedValue: LibraryListStore(status: 2, username: username))
        _finished = StateObject(wrappedValue: LibraryListStore(status: 3, username: username))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $selectedFilter) {
                ForEach(UserBookFilter.allCases, id: \.self) { filter in Text(filter.title).tag(filter) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal)
            ZStack {
                library(wanted, filter: .wantToRead)
                library(reading, filter: .currentlyReading)
                library(finished, filter: .finished)
            }
        }
        .navigationTitle("@\(username)")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .hardcoverAccountDidChange)) { _ in
            wanted.reset(); reading.reset(); finished.reset()
            Task {
                switch selectedFilter {
                case .wantToRead: await wanted.load()
                case .currentlyReading: await reading.load()
                case .finished: await finished.load()
                }
            }
        }
    }

    private func library(_ store: LibraryListStore, filter: UserBookFilter) -> some View {
        UserLibrarySection(store: store, isActive: selectedFilter == filter)
            .opacity(selectedFilter == filter ? 1 : 0)
            .allowsHitTesting(selectedFilter == filter)
            .accessibilityHidden(selectedFilter != filter)
    }
}

private struct UserLibrarySection: View {
    @ObservedObject var store: LibraryListStore
    let isActive: Bool
    @State private var selectedBook: BookProgress?

    var body: some View {
        List {
            if let error = store.error {
                InlineLoadError(message: error) { Task { await store.load(refresh: true) } }
            }
            if store.isLoading { ProgressView().frame(maxWidth: .infinity) }
            ForEach(store.books) { book in
                BookRow(book: book) { selectedBook = book }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            if store.books.isEmpty && !store.isLoading && store.error == nil {
                ContentUnavailableView("No books found", systemImage: "books.vertical")
            }
            if store.isLoadingMore { ProgressView().frame(maxWidth: .infinity) }
            else if store.hasMore && !store.isLoading {
                Button("Load More", systemImage: "arrow.down") { Task { await store.loadMore() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .listStyle(.plain)
        .refreshable { await store.load(refresh: true) }
        .task(id: isActive) { if isActive { await store.load() } }
        .navigationDestination(isPresented: Binding(get: { selectedBook != nil }, set: { if !$0 { selectedBook = nil } })) {
            if let selectedBook { BookDetailView(book: selectedBook, showFinishAction: false, isOwnBook: false) }
        }
    }
}
