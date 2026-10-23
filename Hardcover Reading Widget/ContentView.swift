import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var library = LibraryListStore(status: 2)
    @ObservedObject private var activity = ReadingActivityStore.shared
    @AppStorage("HardcoverAuthRevision", store: AppGroup.defaults) private var authRevision = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    @State private var readingPath: [BookProgress] = []
    @State private var showingSettings = false
    @State private var showingSupporterPack = false
    @State private var checkedOnboarding = false
    @State private var progressBook: BookProgress?
    @State private var finishBook: BookProgress?
    @State private var sessionBook: BookProgress?
    @State private var deadlineBook: BookProgress?
    @State private var removeBook: BookProgress?
    @State private var workingBookID: String?
    @State private var actionError: String?
    @State private var finishedTitle: String?
    @State private var quoteLink: QuoteDeepLink?
    @State private var showingGoals = false
    @State private var goalID: Int?
    @AppStorage("ShowReadingStreak", store: AppGroup.defaults) private var showReadingStreak = true

    private struct QuoteDeepLink: Identifiable {
        let id = UUID()
        let quoteID: Int
        let bookID: Int
        let bookTitle: String
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Reading", systemImage: "book", value: 0) { readingView }
            Tab("Library", systemImage: "books.vertical", value: 1) { LibraryHubView() }
            Tab("Explore", systemImage: "safari", value: 2) { ExplorerView { _ in } }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: 3) { ProfileView() }
            Tab(value: 4, role: .search) { SearchBooksView { _ in } }
        }
        .tabViewStyle(.sidebarAdaptable)
        .safeAreaInset(edge: .top, spacing: 0) { OfflineQueueBanner() }
        .task(id: authRevision) {
            readingPath = []
            progressBook = nil
            finishBook = nil
            sessionBook = nil
            deadlineBook = nil
            activity.reload()
            await OfflineWriteQueue.shared.accountChanged()
            await library.load()
            if !checkedOnboarding {
                checkedOnboarding = true
                showingSettings = !HardcoverConfig.isSignedIn
            }
        }
        .task {
            await SupporterStore.refreshSharedEntitlement()
            await OfflineWriteQueue.shared.drain()
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
        .sheet(isPresented: $showingSupporterPack) {
            NavigationStack {
                TipJarView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingSupporterPack = false }
                        }
                    }
            }
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
        .sheet(item: $sessionBook) { book in
            ReadingSessionView(book: book) { updated in library.apply(book: updated) }
        }
        .sheet(item: $deadlineBook) { book in
            ReadingDeadlineView(book: book)
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
                if (showReadingStreak && activity.metrics.currentStreak > 0) || activity.activeSession != nil {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: activity.activeSession == nil ? "flame.fill" : "timer")
                                .font(.title2)
                                .foregroundStyle(activity.activeSession == nil ? Color.orange : Color.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                if let session = activity.activeSession {
                                    Text("Reading session active").font(.headline)
                                    Text(session.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                } else {
                                    Text("\(activity.metrics.currentStreak)-day reading streak").font(.headline)
                                    Text("Keep it going today").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let session = activity.activeSession {
                                Button("Open") {
                                    sessionBook = library.books.first { $0.bookId == session.bookID }
                                        ?? session.asBookProgress
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
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
                    BookRow(book: book,
                        supplementalText: ReadingPacePresentation.summary(
                            book: book, deadline: activity.deadline(for: book.bookId)),
                        isWorking: workingBookID == book.id,
                        actionIcon: "slider.horizontal.3", actionLabel: "Update progress",
                        onAction: { progressBook = book }, onOpen: { readingPath.append(book) })
                        .contextMenu {
                            Button("Start reading session", systemImage: "timer") { sessionBook = book }
                            Button("Reading deadline", systemImage: "calendar.badge.clock") { deadlineBook = book }
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
        let account = HardcoverConfig.accountIdentifier
        do {
            let own = try await BookPersonalActions.requireOwnBook(bookID: source.bookId, authorization: account)
            guard let id = own.userBookId else { throw BookPersonalActions.Failure.missingBook }
            let success: Bool
            if remove { success = await OfflineWriteQueue.shared.perform(.delete(userBookID: id)) }
            else { success = await OfflineWriteQueue.shared.perform(.status(userBookID: id, statusID: 1, userDate: nil)) }
            guard success else { throw BookPersonalActions.Failure.saveFailed }
            guard account == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            library.remove(id: own.id)
            WidgetSync.libraryChanged(statuses: remove ? [own.statusId ?? 2] : [own.statusId ?? 2, 1])
        } catch { actionError = error.localizedDescription }
    }

    private func openURL(_ url: URL) {
        guard url.scheme?.lowercased() == "softcover" else { return }
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { values.first { $0.name == key }?.value }
        let host = url.host?.lowercased() ?? ""
        progressBook = nil; finishBook = nil; sessionBook = nil; deadlineBook = nil
        showingSettings = false; showingSupporterPack = false
        if host == "goals" || url.path.contains("/goals") {
            goalID = value("goalId").flatMap(Int.init)
            selectedTab = 3
            showingGoals = true
        } else if host == "quote" || url.path.contains("/quote") {
            guard let quoteID = value("quoteId").flatMap(Int.init), let bookID = value("bookId").flatMap(Int.init) else { return }
            quoteLink = QuoteDeepLink(quoteID: quoteID, bookID: bookID, bookTitle: value("bookTitle") ?? "")
        } else if host == "support" || url.path.contains("/support") {
            showingSupporterPack = true
        } else if host == "session" || url.path.contains("/session") {
            guard let session = activity.activeSession else { return }
            sessionBook = library.books.first { $0.bookId == session.bookID } ?? session.asBookProgress
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

private extension ActiveReadingSession {
    var asBookProgress: BookProgress {
        BookProgress(id: "session-\(bookID)", title: title, author: author, progress: 0,
                     totalPages: isAudiobook ? 0 : totalUnits, currentPage: isAudiobook ? 0 : startingUnits,
                     bookId: bookID, userBookId: userBookID, editionId: editionID, originalTitle: title,
                     isAudiobook: isAudiobook, totalMinutes: isAudiobook ? totalUnits : 0,
                     currentMinute: isAudiobook ? startingUnits : 0, statusId: 2)
    }
}

#Preview { ContentView() }
