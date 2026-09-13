import SwiftUI

struct WantToReadView: View {
    @StateObject private var store = LibraryListStore(status: 1)
    @AppStorage("HardcoverAPIKey", store: AppGroup.defaults) private var apiKey = ""
    @AppStorage("WantToReadSortOrder", store: AppGroup.defaults) private var selectedSort: WantToReadSort = .nearestRelease
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var selectedFilter: WantToReadFilter = .all
    @State private var referenceDate = Date()
    @State private var visibleBooks: [BookProgress] = []
    @State private var selectedBook: BookProgress?
    @State private var pendingDelete: BookProgress?
    @State private var workingID: String?
    @State private var actionError: String?
    @State private var showingSettings = false
    @State private var mutedIDs = NotificationManager.mutedReleaseIds
    @State private var notificationsEnabled = NotificationManager.isEnabled
    let onComplete: (Bool) -> Void

    private var filterRequest: String { apiKey + "|" + searchText + "|" + selectedFilter.rawValue + "|" + selectedSort.rawValue }
    private var needsCompleteList: Bool { selectedSort != .recentlyAdded || selectedFilter != .all || !searchText.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error {
                    InlineLoadError(message: error) { Task { await loadBooks(refresh: true) } }
                }
                if let actionError {
                    InlineLoadError(message: actionError) { self.actionError = nil }
                }
                if store.isLoading && store.books.isEmpty {
                    ProgressView("Loading your books...")
                }
                ForEach(visibleBooks) { book in
                    BookRow(
                        book: book,
                        releaseReferenceDate: referenceDate,
                        isWorking: workingID == book.id,
                        actionIcon: "book",
                        actionLabel: "Start Reading",
                        onAction: { Task { await startReading(book) } },
                        onOpen: { selectedBook = book }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = book } label: { Label("Remove", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button { Task { await startReading(book) } } label: { Label("Start Reading", systemImage: "book") }
                        if selectedFilter == .upcoming, notificationsEnabled, let id = book.bookId {
                            Button { Task { await toggleMute(book) } } label: {
                                Label(mutedIDs.contains(id) ? "Enable notifications" : "Mute notifications",
                                      systemImage: mutedIDs.contains(id) ? "bell" : "bell.slash")
                            }
                        }
                        Button(role: .destructive) { pendingDelete = book } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                if store.hasMore {
                    HStack {
                        Spacer()
                        if store.isLoadingMore {
                            ProgressView("Loading more books...")
                        } else {
                            Button("Load more") { Task { await store.loadMore() } }
                        }
                        Spacer()
                    }
                    .task { if !needsCompleteList { await store.loadMore() } }
                }
                if !store.isLoading, !store.hasMore, visibleBooks.isEmpty, store.error == nil {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No books here" : "No results",
                        systemImage: "bookmark"
                    )
                }
            }
            .listStyle(.plain)
            .navigationTitle("Want to Read")
            .searchable(text: $searchText, prompt: Text("Title or author"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(WantToReadFilter.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                    } label: {
                        Label(LocalizedStringKey(selectedFilter.rawValue), systemImage: "line.3.horizontal.decrease")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $selectedSort) {
                            ForEach(WantToReadSort.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                        }
                    } label: {
                        Label("Sort by", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityValue(Text(LocalizedStringKey(selectedSort.title)))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(item: $selectedBook) { book in BookDetailView(book: book) }
            .sheet(isPresented: $showingSettings) { ApiKeySettingsView { _ in } }
            .confirmationDialog("Remove from Want to Read?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { book in
                Button("Remove", role: .destructive) { Task { await remove(book) } }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { Text($0.title) }
            .task(id: apiKey) {
                selectedBook = nil
                await loadBooks()
            }
            .task(id: filterRequest) {
                refreshVisibleBooks()
                guard needsCompleteList else { return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard store.error == nil else { return }
                await store.ensureAllLoaded()
            }
            .onChange(of: store.books) { _, _ in refreshVisibleBooks() }
            .onChange(of: searchText) { _, _ in refreshVisibleBooks() }
            .onChange(of: selectedFilter) { _, _ in refreshVisibleBooks() }
            .onChange(of: selectedSort) { _, _ in refreshVisibleBooks() }
            .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in
                Task { await loadBooks(refresh: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                refreshDay()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshDay() }
            }
            .onAppear {
                notificationsEnabled = NotificationManager.isEnabled
                mutedIDs = NotificationManager.mutedReleaseIds
                refreshDay()
            }
            .refreshable { await loadBooks(refresh: true) }
        }
    }

    private func refreshVisibleBooks() {
        visibleBooks = WantToReadPresentation.books(store.books, query: searchText, filter: selectedFilter,
                                                    sort: selectedSort, now: referenceDate)
    }

    private func refreshDay() {
        referenceDate = Date()
        refreshVisibleBooks()
    }

    private func loadBooks(refresh: Bool = false) async {
        await store.load(refresh: refresh)
        if needsCompleteList, store.error == nil { await store.ensureAllLoaded() }
        refreshVisibleBooks()
    }

    private func startReading(_ book: BookProgress) async {
        guard workingID == nil, let id = book.userBookId else { return }
        workingID = book.id
        let authorization = HardcoverConfig.authorizationHeaderValue
        defer { workingID = nil }
        do {
            let success = try await HardcoverReadScope.checked { await HardcoverService.updateUserBookStatus(userBookId: id, statusId: 2) }
            guard authorization == HardcoverConfig.authorizationHeaderValue else { return }
            guard success else { throw HardcoverNetworkError.invalidResponse }
            store.remove(id: book.id)
            WidgetSync.libraryChanged(statuses: [1, 2])
            onComplete(true)
        } catch { actionError = error.localizedDescription }
    }

    private func remove(_ book: BookProgress) async {
        guard workingID == nil, let id = book.userBookId else { return }
        workingID = book.id
        pendingDelete = nil
        let authorization = HardcoverConfig.authorizationHeaderValue
        defer { workingID = nil }
        do {
            let success = try await HardcoverReadScope.checked { await HardcoverService.deleteUserBook(userBookId: id) }
            guard authorization == HardcoverConfig.authorizationHeaderValue else { return }
            guard success else { throw HardcoverNetworkError.invalidResponse }
            store.remove(id: book.id)
            WidgetSync.libraryChanged(statuses: [1])
        } catch { actionError = error.localizedDescription }
    }

    private func toggleMute(_ book: BookProgress) async {
        guard let id = book.bookId else { return }
        let muted = mutedIDs.contains(id)
        NotificationManager.setMuted(!muted, for: id)
        mutedIDs = NotificationManager.mutedReleaseIds
        if muted, let date = book.parsedReleaseDate {
            await NotificationManager.scheduleReleaseNotification(for: HardcoverService.UpcomingRelease(
                id: id, bookId: id, title: book.title, author: book.author, releaseDate: date, coverImageData: book.coverImageData
            ))
        } else { await NotificationManager.removeNotification(for: id) }
    }
}
