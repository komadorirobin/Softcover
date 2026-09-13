import SwiftUI

struct CatalogEntitySearch: View {
    let kind: CatalogService.EntityKind
    let service: CatalogService
    let excluded: Set<Int>
    let onSelect: (CatalogEntity) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CatalogEntity] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page = 1
    @State private var hasMore = false
    @State private var completedQuery = ""

    private var title: LocalizedStringKey {
        switch kind {
        case .author: return "Select contributor"
        case .series: return "Select series"
        case .publisher: return "Select publisher"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { entity in
                    Button {
                        onSelect(entity)
                        dismiss()
                    } label: {
                        HStack {
                            Text(entity.displayName).foregroundStyle(.primary)
                            Spacer()
                            if excluded.contains(entity.id) { Image(systemName: "checkmark") }
                        }
                    }
                    .disabled(excluded.contains(entity.id) || completedQuery != query)
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await search(reset: true) } }
                } else if !loading, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, results.isEmpty {
                    Text("No results").foregroundStyle(.secondary)
                }
                if hasMore, completedQuery == query {
                    Button("Load more") { Task { await search(reset: false) } }.disabled(loading)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    await search(reset: true)
                } catch { }
            }
        }
    }

    @MainActor private func search(reset: Bool) async {
        let requestedQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if reset {
            results = []
            page = 1
            hasMore = false
        }
        error = nil
        guard !trimmed.isEmpty else { loading = false; return }
        loading = true
        do {
            let result = try await service.search(trimmed, kind: kind, page: page)
            guard !Task.isCancelled, query == requestedQuery else { return }
            let existing = Set(results.map(\.id))
            results += result.entities.filter { !existing.contains($0.id) }
            hasMore = result.hasMore
            page += 1
            completedQuery = requestedQuery
        } catch {
            guard !Task.isCancelled, query == requestedQuery else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct CatalogCoverEditionPicker: View {
    let bookID: Int
    let currentID: Int?
    let service: CatalogService
    let onSelect: (CatalogEditionSummary) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editions: [CatalogEditionSummary] = []
    @State private var offset = 0
    @State private var loading = false
    @State private var hasMore = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(editions) { edition in
                    Button {
                        onSelect(edition)
                        dismiss()
                    } label: {
                        HStack {
                            CatalogEditionLabel(edition: edition).foregroundStyle(.primary)
                            Spacer()
                            if currentID == edition.id { Image(systemName: "checkmark") }
                        }
                    }
                    .disabled(edition.image?.url == nil)
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).foregroundStyle(.secondary) }
                if hasMore || error != nil {
                    Button(error == nil ? "Load more" : "Retry") { Task { await loadMore() } }.disabled(loading)
                }
            }
            .navigationTitle("Choose cover edition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await loadMore() }
        }
    }

    @MainActor private func loadMore() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let page = try await service.editions(bookID: bookID, offset: offset)
            let existing = Set(editions.map(\.id))
            editions += page.filter { !existing.contains($0.id) }
            offset += page.count
            hasMore = page.count == 50
        } catch { self.error = error.localizedDescription }
    }
}

extension BookProgress {
    func refreshingCatalogMetadata() async throws -> BookProgress {
        guard let bookId else { return self }
        let service = CatalogService.live()
        let catalogBook = try await service.book(id: bookId)
        let edition: CatalogEdition?
        if let editionId { edition = try await service.edition(id: editionId) }
        else { edition = nil }
        var updated = self
        updated.originalTitle = catalogBook.title ?? originalTitle
        updated.title = edition?.title ?? catalogBook.title ?? title
        updated.bookDescription = catalogBook.description
        updated.releaseDate = edition?.releaseDate ?? catalogBook.releaseDate
        let contributors = edition?.contributions ?? catalogBook.contributions
        let names = contributors.compactMap { $0.author?.name }
        if !names.isEmpty { updated.author = names.joined(separator: ", ") }
        let imageURL = edition?.image?.url ?? catalogBook.image?.url
        if updated.coverImageUrl != imageURL { updated.coverImageData = nil }
        updated.coverImageUrl = imageURL
        if let edition {
            updated.totalPages = edition.pages ?? 0
            updated.isAudiobook = edition.readingFormatID == 2
            updated.totalMinutes = (edition.audioSeconds ?? 0) / 60
        }
        return updated
    }
}
