import SwiftUI

@MainActor
final class LibraryListStore: ObservableObject {
    @Published private(set) var books: [BookProgress] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published private(set) var error: String?
    let status: Int
    let username: String?
    private var offset = 0
    private var generation = UUID()
    private var account = ""
    private var loaded = false

    init(status: Int, username: String? = nil) { self.status = status; self.username = username }

    func reset() {
        generation = UUID()
        books = []
        offset = 0
        hasMore = true
        loaded = false
        isLoading = false
        isLoadingMore = false
        error = nil
    }

    func load(refresh: Bool = false) async {
        let authorization = HardcoverConfig.authorizationHeaderValue
        if account != authorization {
            reset()
            account = authorization
            if username == nil, let snapshot = LibrarySnapshot.load(status: status) {
                books = snapshot.books
                offset = books.count
                hasMore = !snapshot.complete
            }
        }
        guard refresh || (!loaded && !isLoading) else { return }
        let request = UUID()
        generation = request
        isLoading = true
        isLoadingMore = false
        error = nil
        defer { if generation == request { isLoading = false } }
        do {
            let page = try await LibraryAPI.page(status: status, username: username, fresh: refresh)
            try Task.checkCancellation()
            guard generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            books = unique(page.books)
            offset = page.nextOffset
            hasMore = page.hasMore
            loaded = true
            persist()
        } catch is CancellationError { }
        catch {
            guard generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        let request = generation
        isLoadingMore = true
        error = nil
        defer { if generation == request { isLoadingMore = false } }
        do {
            let page = try await LibraryAPI.page(status: status, offset: offset, username: username)
            try Task.checkCancellation()
            guard generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            books = unique(books + page.books)
            offset = page.nextOffset
            hasMore = page.hasMore
            persist()
        } catch is CancellationError { }
        catch {
            guard generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            self.error = error.localizedDescription
        }
    }

    func ensureAllLoaded() async {
        if !loaded { await load() }
        while !Task.isCancelled && hasMore && error == nil {
            if isLoading || isLoadingMore {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            } else { await loadMore() }
        }
    }

    func apply(book: BookProgress) {
        guard account == HardcoverConfig.authorizationHeaderValue else { return }
        guard book.statusId == nil || book.statusId == status else { remove(id: book.id); return }
        if let index = books.firstIndex(where: { $0.id == book.id }) { books[index] = book }
        if username == nil { LibrarySnapshot.update(book: book) }
    }

    func remove(id: String) {
        guard account == HardcoverConfig.authorizationHeaderValue else { return }
        if let index = books.firstIndex(where: { $0.id == id }) {
            books.remove(at: index)
            offset = max(0, offset - 1)
        }
        loaded = false
        if username == nil { LibrarySnapshot.invalidate(status: status) }
    }

    private func unique(_ values: [BookProgress]) -> [BookProgress] {
        var ids = Set<String>()
        return values.filter { ids.insert($0.id).inserted }
    }

    private func persist() {
        guard username == nil, account == HardcoverConfig.authorizationHeaderValue else { return }
        LibrarySnapshot.save(books, status: status, complete: !hasMore)
    }
}

struct InlineLoadError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityHidden(true)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: retry) { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                .accessibilityLabel("Try Again")
        }
        .foregroundStyle(.secondary)
    }
}
