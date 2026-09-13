import SwiftUI

struct HistoryView: View {
    @StateObject private var store = HistoryListStore()
    @State private var searchText = ""
    @State private var selectedBook: BookProgress?

    private var matches: [FinishedBookEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if let error = store.error {
                InlineLoadError(message: error) {
                    Task {
                        await store.load(refresh: true)
                        if !searchText.isEmpty { await store.ensureAllLoaded() }
                    }
                }
            }
            if store.isLoading || store.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            ForEach(matches) { entry in
                BookRow(book: progress(for: entry), subtitle: subtitle(for: entry)) {
                    selectedBook = progress(for: entry)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            if matches.isEmpty && !store.isLoading && !store.isLoadingMore && store.error == nil {
                ContentUnavailableView(searchText.isEmpty ? "No books in your reading history" : "No matches found", systemImage: "clock")
            }
            if store.hasMore && !store.isLoading && !store.isLoadingMore {
                Button("Load More", systemImage: "arrow.down") { Task { await store.loadMore() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Reading History")
        .searchable(text: $searchText)
        .task { await store.load() }
        .task(id: searchText) {
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await store.ensureAllLoaded()
        }
        .refreshable { await store.load(refresh: true) }
        .navigationDestination(isPresented: Binding(get: { selectedBook != nil }, set: { if !$0 { selectedBook = nil } })) {
            if let selectedBook { BookDetailView(book: selectedBook, showFinishAction: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hardcoverAccountDidChange)) { _ in
            store.reset(); selectedBook = nil
            Task { await store.load() }
        }
    }

    private func progress(for entry: FinishedBookEntry) -> BookProgress {
        BookProgress(id: "\(entry.userBookId ?? entry.id)", title: entry.title, author: entry.author,
                     coverImageData: entry.coverImageData, coverImageUrl: entry.coverImageUrl,
                     progress: 1, totalPages: 0, currentPage: 0, bookId: entry.bookId,
                     userBookId: entry.userBookId, editionId: nil, originalTitle: entry.title, userRating: entry.rating, statusId: 3)
    }

    private func subtitle(for entry: FinishedBookEntry) -> String {
        let date = entry.finishedAt.formatted(date: .abbreviated, time: .omitted)
        guard let rating = entry.rating else { return date }
        return date + " - " + String(format: NSLocalizedString("Rating: %.1f/5", comment: ""), rating)
    }
}
