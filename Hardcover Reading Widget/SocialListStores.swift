import Foundation
import Combine

@MainActor
final class ExploreLoadState<Item>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var snapshots: [String: [Item]] = [:]
    private var generation = UUID()
    private var account = ""

    func load(key: String, refresh: Bool = false, fetch: () async throws -> [Item]) async {
        let authorization = HardcoverConfig.authorizationHeaderValue
        if account != authorization { reset(); account = authorization }
        let request = UUID()
        generation = request
        error = nil
        if let cached = snapshots[key] {
            items = cached
            if !refresh { isLoading = false; return }
        }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            try Task.checkCancellation()
            let result = try await fetch()
            try Task.checkCancellation()
            guard generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            snapshots[key] = result
            items = result
        } catch {
            guard !Task.isCancelled, generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            self.error = error.localizedDescription
        }
    }

    func reset() {
        generation = UUID()
        snapshots.removeAll()
        items = []
        error = nil
        isLoading = false
    }
}

@MainActor
final class HistoryListStore: ObservableObject {
    @Published private(set) var entries: [FinishedBookEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    private var offset = 0
    private var generation = UUID()
    private var loaded = false
    private var account = ""

    func reset() {
        generation = UUID(); entries = []; offset = 0; hasMore = true
        loaded = false; error = nil; isLoading = false; isLoadingMore = false
    }

    func load(refresh: Bool = false) async {
        let authorization = HardcoverConfig.authorizationHeaderValue
        if account != authorization { reset(); account = authorization }
        guard refresh || !loaded else { return }
        let request = UUID()
        generation = request
        isLoading = true; isLoadingMore = false; error = nil
        defer { if generation == request { isLoading = false } }
        do {
            try Task.checkCancellation()
            let page = try await LibraryHistoryAPI.page(offset: 0, fresh: refresh)
            try Task.checkCancellation()
            guard request == generation, account == HardcoverConfig.authorizationHeaderValue else { return }
            entries = page.entries
            offset = page.nextOffset
            hasMore = page.hasMore
            loaded = true
        } catch {
            guard !Task.isCancelled, request == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !Task.isCancelled, !isLoading, !isLoadingMore, hasMore else { return }
        let request = generation
        isLoadingMore = true; error = nil
        defer { if request == generation { isLoadingMore = false } }
        do {
            try Task.checkCancellation()
            let page = try await LibraryHistoryAPI.page(offset: offset)
            try Task.checkCancellation()
            guard request == generation, account == HardcoverConfig.authorizationHeaderValue else { return }
            var seen = Set(entries.map(\.id))
            entries.append(contentsOf: page.entries.filter { seen.insert($0.id).inserted })
            offset = page.nextOffset
            hasMore = page.hasMore
        } catch {
            guard !Task.isCancelled, request == generation else { return }
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
}
