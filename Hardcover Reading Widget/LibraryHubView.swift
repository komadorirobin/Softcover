import SwiftUI

struct LibraryShelf: Codable, Hashable, Identifiable {
    let id: Int
    let title: String
    let icon: String

    static let defaults: [LibraryShelf] = [
        .init(id: 1, title: "Want to Read", icon: "bookmark"),
        .init(id: 2, title: "Reading", icon: "book"),
        .init(id: 4, title: "Paused", icon: "pause.circle"),
        .init(id: 3, title: "Read", icon: "checkmark.circle"),
        .init(id: 5, title: "Did Not Finish", icon: "xmark.circle"),
        .init(id: 99, title: "Owned", icon: "books.vertical.fill")
    ]
}

enum LibraryShelfPreferences {
    static let key = "LibraryShelfOrder"
    static func load() -> [LibraryShelf] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else { return LibraryShelf.defaults }
        let map = Dictionary(uniqueKeysWithValues: LibraryShelf.defaults.map { ($0.id, $0) })
        var chosen = ids.compactMap { map[$0] }
        if !AppGroup.defaults.bool(forKey: "LibraryShelfOwnedMigration"), let owned = map[99], !chosen.contains(owned) {
            chosen.append(owned)
            AppGroup.defaults.set(true, forKey: "LibraryShelfOwnedMigration")
            save(chosen)
        }
        return chosen.isEmpty ? LibraryShelf.defaults : chosen
    }
    static func save(_ shelves: [LibraryShelf]) {
        if let data = try? JSONEncoder().encode(shelves.map(\.id)) { AppGroup.defaults.set(data, forKey: key) }
        NotificationCenter.default.post(name: .libraryShelfSettingsChanged, object: nil)
    }
}

extension Notification.Name { static let libraryShelfSettingsChanged = Notification.Name("LibraryShelfSettingsChanged") }

struct LibraryHubView: View {
    @AppStorage("LibrarySwipeEnabled", store: AppGroup.defaults) private var swipeEnabled = true
    @State private var shelves = LibraryShelfPreferences.load()
    @State private var selected = LibraryShelfPreferences.load().first?.id ?? 1
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelves) { shelf in
                            Button { selected = shelf.id } label: {
                                Label(shelf.title, systemImage: shelf.icon)
                                    .font(.subheadline.weight(selected == shelf.id ? .semibold : .regular))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(selected == shelf.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal).padding(.vertical, 8)
                }
                if swipeEnabled {
                    TabView(selection: $selected) {
                        ForEach(shelves) { shelf in
                            Group { if shelf.id == 99 { OwnedShelfPage() } else { LibraryShelfPage(shelf: shelf) } }.tag(shelf.id)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                } else if let shelf = shelves.first(where: { $0.id == selected }) {
                    if shelf.id == 99 { OwnedShelfPage() } else { LibraryShelfPage(shelf: shelf) }
                }
            }
            .navigationTitle(shelves.first(where: { $0.id == selected })?.title ?? "Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Shelves", systemImage: "slider.horizontal.3") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) { LibraryShelfSettingsView() }
            .onReceive(NotificationCenter.default.publisher(for: .libraryShelfSettingsChanged)) { _ in
                shelves = LibraryShelfPreferences.load()
                if !shelves.contains(where: { $0.id == selected }) { selected = shelves.first?.id ?? 1 }
            }
        }
    }
}

private struct LibraryShelfPage: View {
    let shelf: LibraryShelf
    @StateObject private var store: LibraryListStore
    @State private var workingID: String?
    @State private var error: String?
    @State private var pendingRemoval: BookProgress?
    @State private var removalTask: Task<Void, Never>?
    @State private var selectedBook: BookProgress?

    init(shelf: LibraryShelf) {
        self.shelf = shelf
        _store = StateObject(wrappedValue: LibraryListStore(status: shelf.id))
    }

    var body: some View {
        List {
            if let error = store.error { InlineLoadError(message: error) { Task { await store.load(refresh: true) } } }
            if store.isLoading && store.books.isEmpty { ProgressView("Loading \(shelf.title.lowercased())…").frame(maxWidth: .infinity, minHeight: 140) }
            if !store.isLoading && store.books.isEmpty && store.error == nil {
                ContentUnavailableView("No books", systemImage: shelf.icon, description: Text("This shelf is empty."))
            }
            ForEach(store.books) { book in
                BookRow(book: book, isWorking: workingID == book.id, onOpen: { selectedBook = book })
                .contextMenu {
                    ForEach(LibraryShelf.defaults.filter { $0.id != shelf.id }) { destination in
                        Button(destination.title, systemImage: destination.icon) { Task { await move(book, to: destination.id) } }
                    }
                    Button("Remove from library", systemImage: "trash", role: .destructive) { stageRemoval(book) }
                }
                .swipeActions(edge: .trailing) {
                    Button("Remove", systemImage: "trash", role: .destructive) { stageRemoval(book) }
                }
            }
            if store.hasMore && !store.books.isEmpty {
                HStack { Spacer(); if store.isLoadingMore { ProgressView() } else { Button("Load more") { Task { await store.loadMore() } } }; Spacer() }
                    .task { if store.error == nil { await store.loadMore() } }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.load(refresh: true) }
        .task { await store.load() }
        .navigationDestination(item: $selectedBook) { book in
            BookDetailView(book: book) { updated in
                if let updated, updated.statusId == shelf.id { store.apply(book: updated) }
                else { store.remove(id: book.id) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let pendingRemoval {
                HStack {
                    Text("Removed \(pendingRemoval.title)").lineLimit(1)
                    Spacer()
                    Button("Undo") { undoRemoval() }.fontWeight(.semibold)
                }.padding().background(.regularMaterial)
            }
        }
        .alert("Action failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .onDisappear { commitRemovalNow() }
    }

    @MainActor private func move(_ source: BookProgress, to status: Int) async {
        guard workingID == nil else { return }; workingID = source.id; defer { workingID = nil }
        do {
            let account = HardcoverConfig.accountIdentifier
            let own = try await BookPersonalActions.requireOwnBook(bookID: source.bookId, authorization: account)
            guard let id = own.userBookId, await OfflineWriteQueue.shared.perform(.status(userBookID: id, statusID: status, userDate: nil)) else { throw BookPersonalActions.Failure.saveFailed }
            store.remove(id: source.id); WidgetSync.libraryChanged(statuses: [shelf.id, status])
        } catch { self.error = error.localizedDescription }
    }

    private func stageRemoval(_ book: BookProgress) {
        commitRemovalNow(); pendingRemoval = book; store.remove(id: book.id)
        removalTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run { commitRemovalNow() }
        }
    }
    private func undoRemoval() {
        removalTask?.cancel(); removalTask = nil
        if let book = pendingRemoval { store.apply(book: book) }
        pendingRemoval = nil
    }
    private func commitRemovalNow() {
        removalTask?.cancel(); removalTask = nil
        guard let book = pendingRemoval else { return }; pendingRemoval = nil
        Task {
            guard let id = book.userBookId, await OfflineWriteQueue.shared.perform(.delete(userBookID: id)) else {
                await MainActor.run { store.apply(book: book); error = "The book could not be removed." }
                return
            }
            WidgetSync.libraryChanged(statuses: [shelf.id])
        }
    }
}

struct LibraryShelfSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shelves = LibraryShelfPreferences.load()
    @AppStorage("LibrarySwipeEnabled", store: AppGroup.defaults) private var swipeEnabled = true

    var body: some View {
        NavigationStack {
            List {
                Section { Toggle("Swipe between shelves", isOn: $swipeEnabled) }
                Section("Visible shelves") {
                    ForEach(shelves) { shelf in Label(shelf.title, systemImage: shelf.icon) }
                    .onMove { source, destination in shelves.move(fromOffsets: source, toOffset: destination) }
                    .onDelete { offsets in if shelves.count - offsets.count >= 1 { shelves.remove(atOffsets: offsets) } }
                }
                let hidden = LibraryShelf.defaults.filter { !shelves.contains($0) }
                if !hidden.isEmpty {
                    Section("Hidden shelves") {
                        ForEach(hidden) { shelf in
                            Button { shelves.append(shelf) } label: { Label("Show \(shelf.title)", systemImage: "plus.circle") }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Library Shelves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { LibraryShelfPreferences.save(shelves); dismiss() } }
            }
        }
    }
}
