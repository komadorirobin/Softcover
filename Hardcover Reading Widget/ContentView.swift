import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var library = LibraryListStore(status: 2)
    @AppStorage("HardcoverAPIKey", store: AppGroup.defaults) private var apiKey = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    @State private var readingPath: [BookProgress] = []
    @State private var showingSettings = false
    @State private var checkedOnboarding = false
    @State private var progressBook: BookProgress?
    @State private var finishBook: BookProgress?
    @State private var removeBook: BookProgress?
    @State private var workingBookID: String?
    @State private var actionError: String?
    @State private var finishedTitle: String?
    @State private var quoteLink: QuoteDeepLink?
    @State private var showingGoals = false
    @State private var goalID: Int?

    private struct QuoteDeepLink: Identifiable {
        let id = UUID()
        let quoteID: Int
        let bookID: Int
        let bookTitle: String
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Reading", systemImage: "book", value: 0) { readingView }
            Tab("Want to Read", systemImage: "bookmark", value: 1) {
                WantToReadView { started in
                    if started { selectedTab = 0 }
                }
            }
            Tab("Explore", systemImage: "safari", value: 2) { ExplorerView { _ in } }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: 3) { ProfileView() }
            Tab(value: 4, role: .search) { SearchBooksView { _ in } }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task(id: apiKey) {
            readingPath = []
            progressBook = nil
            finishBook = nil
            await library.load()
            if !checkedOnboarding {
                checkedOnboarding = true
                showingSettings = HardcoverConfig.apiKey.isEmpty
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { note in
            let statuses = note.userInfo?["statuses"] as? Set<Int>
                ?? Set(note.userInfo?["statuses"] as? [Int] ?? [1, 2, 3])
            guard statuses.contains(2) else { return }
            if statuses == [2], let snapshot = LibrarySnapshot.load(status: 2), !snapshot.stale {
                for book in snapshot.books { library.apply(book: book) }
            } else { Task { await library.load(refresh: true) } }
        }
        .sheet(isPresented: $showingSettings) {
            ApiKeySettingsView { _ in Task { await library.load(refresh: true) } }
        }
        .sheet(item: $progressBook) { book in
            ReadingProgressEditor(book: book) { updated in library.apply(book: updated) }
        }
        .sheet(item: $finishBook) { book in
            FinishRateReviewSheet(book: book, markFinished: true) { updated in
                library.remove(id: updated.id)
                finishedTitle = updated.title
                if !reduceMotion { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
        }
        .sheet(item: $quoteLink) { link in
            BookQuotesView(bookId: link.bookID, bookTitle: link.bookTitle,
                editionId: nil, totalPages: nil, highlightQuoteId: link.quoteID)
        }
        .sheet(isPresented: $showingGoals) {
            NavigationStack {
                StatsView(highlightGoalID: goalID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showingGoals = false } }
                    }
            }
        }
        .confirmationDialog("Remove book?", isPresented: Binding(get: { removeBook != nil }, set: { if !$0 { removeBook = nil } }), titleVisibility: .visible) {
            if let book = removeBook {
                Button("Remove from library", role: .destructive) { Task { await updateLibrary(book, remove: true) } }
            }
            Button("Cancel", role: .cancel) { removeBook = nil }
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .onOpenURL(perform: openURL)
    }

    private var readingView: some View {
        NavigationStack(path: $readingPath) {
            List {
                if let title = finishedTitle {
                    HStack(alignment: .top) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Marked as finished").font(.headline)
                                Text(title).font(.subheadline)
                            }
                        } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                        Spacer()
                        Button { finishedTitle = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Dismiss")
                    }
                }
                if let error = library.error {
                    InlineLoadError(message: error) { Task { await library.load(refresh: true) } }
                }
                if library.isLoading && library.books.isEmpty {
                    ProgressView("Loading your books...").frame(maxWidth: .infinity, minHeight: 160)
                        .listRowSeparator(.hidden)
                } else if library.books.isEmpty && library.error == nil {
                    ContentUnavailableView {
                        Label("No books currently reading", systemImage: "books.vertical")
                    } actions: {
                        Button("Search Books", systemImage: "magnifyingglass") { selectedTab = 4 }
                            .frame(minHeight: 44)
                    }.listRowSeparator(.hidden)
                }
                ForEach(library.books) { book in
                    BookRow(book: book, isWorking: workingBookID == book.id,
                        actionIcon: "slider.horizontal.3", actionLabel: "Update progress",
                        onAction: { progressBook = book }, onOpen: { readingPath.append(book) })
                        .contextMenu {
                            Button("Update progress", systemImage: "slider.horizontal.3") { progressBook = book }
                            Button("Mark as finished", systemImage: "checkmark.circle") { finishBook = book }
                            Button("Want to Read", systemImage: "bookmark") { Task { await updateLibrary(book, remove: false) } }
                            Button("Remove from library", systemImage: "trash", role: .destructive) { removeBook = book }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Mark as finished", systemImage: "checkmark") { finishBook = book }.tint(.green)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
                }
                if library.hasMore && !library.books.isEmpty {
                    HStack {
                        Spacer()
                        if library.isLoadingMore { ProgressView() }
                        else { Button("Load more") { Task { await library.loadMore() } }.frame(minHeight: 44) }
                        Spacer()
                    }.task { if library.error == nil { await library.loadMore() } }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Currently Reading")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable { await library.load(refresh: true) }
            .navigationDestination(for: BookProgress.self) { book in
                BookDetailView(book: book, onLibraryChange: { updated in
                    if let updated { library.apply(book: updated) }
                    else { library.remove(id: book.id) }
                })
            }
        }
    }

    @MainActor private func updateLibrary(_ source: BookProgress, remove: Bool) async {
        guard workingBookID == nil else { return }
        workingBookID = source.id
        defer { workingBookID = nil; removeBook = nil }
        let auth = HardcoverConfig.authorizationHeaderValue
        do {
            let own = try await BookPersonalActions.requireOwnBook(bookID: source.bookId, authorization: auth)
            guard let id = own.userBookId else { throw BookPersonalActions.Failure.missingBook }
            let success: Bool
            if remove { success = await HardcoverService.deleteUserBook(userBookId: id) }
            else { success = await HardcoverService.updateUserBookStatus(userBookId: id, statusId: 1) }
            guard success else { throw BookPersonalActions.Failure.saveFailed }
            guard auth == HardcoverConfig.authorizationHeaderValue else { throw HardcoverNetworkError.accountChanged }
            library.remove(id: own.id)
            WidgetSync.libraryChanged(statuses: remove ? [own.statusId ?? 2] : [own.statusId ?? 2, 1])
        } catch { actionError = error.localizedDescription }
    }

    private func openURL(_ url: URL) {
        guard url.scheme?.lowercased() == "softcover" else { return }
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { values.first { $0.name == key }?.value }
        let host = url.host?.lowercased() ?? ""
        progressBook = nil; finishBook = nil; showingSettings = false
        if host == "goals" || url.path.contains("/goals") {
            goalID = value("goalId").flatMap(Int.init)
            selectedTab = 3
            showingGoals = true
        } else if host == "quote" || url.path.contains("/quote") {
            guard let quoteID = value("quoteId").flatMap(Int.init), let bookID = value("bookId").flatMap(Int.init) else { return }
            quoteLink = QuoteDeepLink(quoteID: quoteID, bookID: bookID, bookTitle: value("bookTitle") ?? "")
        } else if host == "upcoming" || host == "book" || url.path.contains("/upcoming") {
            guard let bookID = value("bookId").flatMap(Int.init) else { selectedTab = 1; return }
            let cached = library.books.first { $0.bookId == bookID }
                ?? LibrarySnapshot.load(status: 1)?.books.first { $0.bookId == bookID }
            var book = cached ?? BookProgress(id: "book-\(bookID)", title: NSLocalizedString("Book Details", comment: ""),
                author: "", bookId: bookID, originalTitle: "")
            if let editionID = value("editionId").flatMap(Int.init) { book.editionId = editionID }
            selectedTab = 0
            readingPath = [book]
        }
    }
}

#Preview { ContentView() }
