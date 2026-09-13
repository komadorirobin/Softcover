import SwiftUI

struct SearchBooksView: View {
    @StateObject private var store = BookSearchStore()
    @State private var query = ""
    @State private var searchType = SearchType.books
    @State private var selectedBook: BookProgress?
    @State private var history: [String] = []
    @State private var workingID: Int?
    @State private var pendingBook: BookProgress?
    @State private var editions: [Edition] = []
    @State private var showingEditions = false
    @State private var showingSettings = false
    @State private var showingScanner = false
    @State private var actionError: String?
    @State private var searchRevision = 0
    @AppStorage("HardcoverAPIKey", store: AppGroup.defaults) private var apiKey = ""
    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPicker = false

    let onDone: (Bool) -> Void

    private enum SearchType: String, CaseIterable {
        case books = "Books", users = "Users"
        var queryType: String { self == .books ? "book" : "user" }
    }

    private var request: BookSearchStore.Request {
        .init(text: query, type: searchType.queryType, account: HardcoverConfig.authorizationHeaderValue)
    }
    private var taskID: String { "\(request.account)|\(request.type)|\(request.text)|\(searchRevision)" }
    private var historyKey: String { "SearchHistory.\(HardcoverRequestScheduler.accountKey(request.account))" }

    var body: some View {
        NavigationStack {
            List {
                Picker("Search Type", selection: $searchType) {
                    ForEach(SearchType.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !history.isEmpty {
                        Section {
                            ForEach(history, id: \.self) { term in
                                Button { query = term } label: { Label(term, systemImage: "clock.arrow.circlepath") }
                                    .foregroundStyle(.primary)
                            }
                        } header: {
                            HStack {
                                Text("Recent Searches")
                                Spacer()
                                Button { history = []; AppGroup.defaults.removeObject(forKey: historyKey) } label: {
                                    Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                                }
                                .accessibilityLabel("Clear search history")
                            }
                        }
                    }
                } else if store.isLoading {
                    HStack { Spacer(); ProgressView("Searching"); Spacer() }
                        .listRowSeparator(.hidden)
                } else {
                    if let error = store.error {
                        InlineLoadError(message: error) { searchRevision += 1 }
                    }
                    if searchType == .books {
                        ForEach(store.books) { book in
                            BookRow(
                                book: book,
                                subtitle: statusLabel(book.bookId),
                                isWorking: workingID == book.bookId,
                                actionIcon: store.statuses[book.bookId ?? 0] == nil ? "plus" : nil,
                                actionLabel: "Want to Read",
                                onAction: { Task { await quickAdd(book) } },
                                onOpen: { selectedBook = book }
                            )
                        }
                    } else {
                        ForEach(store.users) { user in
                            NavigationLink { UserProfileView(username: user.username) } label: {
                                HStack(spacing: 12) {
                                    AsyncCachedImage(url: user.image.flatMap(URL.init(string:)), maxPixel: 88) {
                                        $0.resizable().scaledToFill()
                                    } placeholder: { Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary) }
                                    .frame(width: 44, height: 44).clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(user.name?.isEmpty == false ? user.name! : user.username).font(.headline)
                                        Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary)
                                        if let bio = user.bio, !bio.isEmpty { Text(bio).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                }
                            }
                        }
                    }
                    if store.hasMore {
                        HStack {
                            Spacer()
                            if store.isLoadingMore { ProgressView() }
                            else { Button("Load more") { Task { await store.loadMore() } } }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .task { await store.loadMore() }
                    }
                    if store.completed && store.error == nil && store.books.isEmpty && store.users.isEmpty {
                        ContentUnavailableView.search(text: query).listRowSeparator(.hidden)
                    }
                }
                if let error = actionError {
                    InlineLoadError(message: error) {
                        if let book = pendingBook { Task { await quickAdd(book) } }
                        else { actionError = nil }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(searchType == .books ? LocalizedStringKey("Title, author, or ISBN") : LocalizedStringKey("Username or name")))
            .onSubmit(of: .search) { rememberQuery(); searchRevision += 1 }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                if searchType == .books {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                            .accessibilityLabel("Scan barcode")
                    }
                }
            }
            .navigationDestination(item: $selectedBook) { BookDetailView(book: $0) }
            .task(id: taskID) {
                await store.search(request)
                if store.completed { rememberQuery() }
            }
            .task(id: apiKey) {
                selectedBook = nil
                pendingBook = nil
                showingEditions = false
                actionError = nil
                history = AppGroup.defaults.stringArray(forKey: historyKey) ?? []
            }
            .sheet(isPresented: $showingSettings) { ApiKeySettingsView { _ in } }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { code in showingScanner = false; searchType = .books; query = code }
            }
            .sheet(isPresented: $showingEditions) {
                if let book = pendingBook {
                    EditionSelectionSheet(bookTitle: book.title, currentEditionId: nil, editions: editions,
                        onCancel: { showingEditions = false; pendingBook = nil },
                        onSave: { editionID in
                            showingEditions = false
                            Task { await add(book, editionID: editionID) }
                        })
                }
            }
        }
    }

    private func statusLabel(_ id: Int?) -> String? {
        switch store.statuses[id ?? 0] {
        case 1: return NSLocalizedString("Want to Read", comment: "")
        case 2: return NSLocalizedString("Currently Reading", comment: "")
        case 3: return NSLocalizedString("Read", comment: "")
        case 5: return NSLocalizedString("Did Not Finish", comment: "")
        default: return nil
        }
    }

    private func rememberQuery() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        history.removeAll { $0 == term }
        history.insert(term, at: 0)
        history = Array(history.prefix(10))
        AppGroup.defaults.set(history, forKey: historyKey)
    }

    @MainActor private func quickAdd(_ book: BookProgress) async {
        guard workingID == nil, let id = book.bookId else { return }
        let account = request.account
        actionError = nil
        pendingBook = book
        workingID = id
        defer { workingID = nil }
        do {
            if skipEditionPicker { await add(book, editionID: nil); return }
            let values = try await HardcoverReadScope.checked { await HardcoverService.fetchEditions(for: id) }
            guard account == request.account else { return }
            if values.count <= 1 { await add(book, editionID: values.first?.id) }
            else { editions = values; showingEditions = true }
        } catch {
            if account == request.account { actionError = error.localizedDescription }
        }
    }

    @MainActor private func add(_ book: BookProgress, editionID: Int?) async {
        guard let id = book.bookId else { return }
        let account = request.account
        workingID = id
        actionError = nil
        defer { workingID = nil }
        do {
            if let existing = try await LibraryAPI.ownBook(bookID: id, fresh: true) {
                guard account == request.account else { return }
                store.setStatus(bookID: id, status: existing.statusId ?? 1)
                pendingBook = nil
                return
            }
            let success = try await HardcoverReadScope.checked {
                await HardcoverService.addBookToWantToRead(bookId: id, editionId: editionID)
            }
            guard account == request.account else { return }
            guard success else { throw HardcoverNetworkError.invalidResponse }
            store.markAdded(id)
            pendingBook = nil
            WidgetSync.libraryChanged(statuses: [1])
            onDone(true)
        } catch {
            if account == request.account { actionError = error.localizedDescription }
        }
    }
}

#Preview { SearchBooksView { _ in } }
