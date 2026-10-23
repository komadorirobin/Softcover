import SwiftUI
import Combine

struct OwnedEditionEntry: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let editionID: Int
    let book: BookProgress
}

enum OwnedEditionsService {
    static let query = """
    query SoftcoverOwnedEditions {
      me {
        lists(where: {slug: {_eq: "owned"}}, limit: 1) {
          list_books(order_by: {created_at: desc}) {
            id edition_id book_id
            book { id title rating release_date cached_contributors image { url } }
            edition { id title pages audio_seconds release_date reading_format { format } image { url } }
          }
        }
      }
    }
    """
    static let markMutation = "mutation SoftcoverOwnEdition($id: Int!) { edition_owned(id: $id) { list_book { id edition_id book_id } } }"
    static let removeMutation = "mutation SoftcoverUnownEdition($id: Int!) { delete_list_book(id: $id) { id } }"

    static func fetch() async throws -> [OwnedEditionEntry] {
        let data = try await LibraryAPI.request(query, fresh: true)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let me = (payload["me"] as? [[String: Any]])?.first,
              let list = (me["lists"] as? [[String: Any]])?.first else { return [] }
        return (list["list_books"] as? [[String: Any]] ?? []).compactMap(decode)
    }

    static func mark(editionID: Int, fallbackBook: BookProgress) async throws -> OwnedEditionEntry {
        let data = try await LibraryAPI.request(markMutation, variables: ["id": editionID], fresh: true)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let wrapper = payload["edition_owned"] as? [String: Any],
              let row = wrapper["list_book"] as? [String: Any],
              let id = row["id"] as? Int else { throw HardcoverNetworkError.invalidResponse }
        return OwnedEditionEntry(id: id, editionID: row["edition_id"] as? Int ?? editionID, book: fallbackBook)
    }

    static func remove(listBookID: Int) async throws {
        let data = try await LibraryAPI.request(removeMutation, variables: ["id": listBookID], fresh: true)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["errors"] == nil,
              let payload = root["data"] as? [String: Any], payload["delete_list_book"] != nil else {
            throw HardcoverNetworkError.invalidResponse
        }
    }

    private static func decode(_ row: [String: Any]) -> OwnedEditionEntry? {
        guard let id = row["id"] as? Int, let editionID = row["edition_id"] as? Int,
              let raw = row["book"] as? [String: Any], let bookID = raw["id"] as? Int else { return nil }
        let edition = row["edition"] as? [String: Any]
        let authors = (raw["cached_contributors"] as? [[String: Any]] ?? []).compactMap { (($0["author"] as? [String: Any])?["name"] as? String) }.joined(separator: ", ")
        let format = ((edition?["reading_format"] as? [String: Any])?["format"] as? String)
        let seconds = edition?["audio_seconds"] as? Int ?? 0
        let audio = HardcoverReadingFormat.isAudiobook(format) || seconds > 0
        let cover = ((edition?["image"] as? [String: Any])?["url"] as? String) ?? ((raw["image"] as? [String: Any])?["url"] as? String)
        let title = (raw["title"] as? String ?? "Untitled").decodedHTMLEntities
        let book = BookProgress(id: "owned-\(id)", title: title, author: authors,
            coverImageUrl: cover, totalPages: edition?["pages"] as? Int ?? 0,
            bookId: bookID, editionId: editionID, originalTitle: title,
            editionAverageRating: raw["rating"] as? Double,
            releaseDate: (edition?["release_date"] as? String) ?? (raw["release_date"] as? String),
            isAudiobook: audio, totalMinutes: seconds / 60, readingFormat: format)
        return OwnedEditionEntry(id: id, editionID: editionID, book: book)
    }
}

@MainActor
final class OwnedEditionsStore: ObservableObject {
    static let shared = OwnedEditionsStore()
    @Published private(set) var entries: [OwnedEditionEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var account = ""
    private init() {}

    func load(refresh: Bool = false) async {
        let current = HardcoverConfig.accountIdentifier
        if account != current { account = current; entries = []; error = nil }
        guard refresh || entries.isEmpty else { return }
        loading = true; defer { loading = false }
        do { entries = try await OwnedEditionsService.fetch(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func entry(editionID: Int?) -> OwnedEditionEntry? { guard let editionID else { return nil }; return entries.first { $0.editionID == editionID } }
    func mark(editionID: Int, book: BookProgress) async throws { entries.append(try await OwnedEditionsService.mark(editionID: editionID, fallbackBook: book)) }
    func remove(_ entry: OwnedEditionEntry) async throws { try await OwnedEditionsService.remove(listBookID: entry.id); entries.removeAll { $0.id == entry.id } }
    func optimisticMark(editionID: Int, book: BookProgress) {
        guard entry(editionID: editionID) == nil else { return }
        entries.append(.init(id: -editionID, editionID: editionID, book: book))
    }
    func optimisticRemove(_ entry: OwnedEditionEntry) { entries.removeAll { $0.id == entry.id } }
}

struct OwnedShelfPage: View {
    @ObservedObject private var store = OwnedEditionsStore.shared
    @State private var selected: BookProgress?
    var body: some View {
        List {
            if let error = store.error { InlineLoadError(message: error) { Task { await store.load(refresh: true) } } }
            if store.loading && store.entries.isEmpty { ProgressView("Loading owned editions…").frame(maxWidth: .infinity, minHeight: 140) }
            ForEach(store.entries) { entry in
                BookRow(book: entry.book, subtitle: entry.book.displayFormat, onOpen: { selected = entry.book })
                    .swipeActions {
                        Button("Unmark", systemImage: "minus.circle", role: .destructive) {
                            Task {
                                if await OfflineWriteQueue.shared.perform(.unown(listBookID: entry.id)) {
                                    store.optimisticRemove(entry)
                                }
                            }
                        }
                    }
            }
            if !store.loading && store.entries.isEmpty && store.error == nil {
                ContentUnavailableView("No owned editions", systemImage: "books.vertical", description: Text("Mark an edition as owned from its book page."))
            }
        }.listStyle(.plain).refreshable { await store.load(refresh: true) }.task { await store.load() }
            .navigationDestination(item: $selected) { BookDetailView(book: $0, isOwnBook: false) }
    }
}
