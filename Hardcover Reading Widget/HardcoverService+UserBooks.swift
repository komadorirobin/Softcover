import Foundation

struct LibraryHistoryPage {
    let entries: [FinishedBookEntry]
    let nextOffset: Int
    let hasMore: Bool
}

enum LibraryHistoryAPI {
    static let pageQuery = CommunityQueries.history

    static func page(offset: Int, limit: Int = 25, fresh: Bool = false) async throws -> LibraryHistoryPage {
        let identity = try await LibraryAPI.identity()
        let data = try await LibraryAPI.request(pageQuery, variables: [
            "userId": identity.id, "limit": limit + 1, "offset": offset
        ], fresh: fresh)
        return try decode(data, offset: offset, limit: limit)
    }

    static func decode(_ data: Data, offset: Int, limit: Int) throws -> LibraryHistoryPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root["data"] as? [String: Any],
              let rows = value["user_book_reads"] as? [[String: Any]] else {
            throw HardcoverNetworkError.invalidResponse
        }
        let entries = try rows.prefix(limit).map { row -> FinishedBookEntry in
            guard let id = row["id"] as? Int,
                  let finished = row["finished_at"] as? String,
                  let date = ReleaseDate.parse(String(finished.prefix(10))),
                  let userBook = row["user_book"] as? [String: Any],
                  let bookID = userBook["book_id"] as? Int,
                  let book = userBook["book"] as? [String: Any],
                  let title = book["title"] as? String else { throw HardcoverNetworkError.invalidResponse }
            let edition = userBook["edition"] as? [String: Any]
            let editionTitle = edition?["title"] as? String
            let contributions = book["contributions"] as? [[String: Any]]
            let author = (contributions?.first?["author"] as? [String: Any])?["name"] as? String
            let image = (edition?["image"] as? [String: Any])?["url"] as? String
                ?? (book["image"] as? [String: Any])?["url"] as? String
            return FinishedBookEntry(id: id, bookId: bookID, userBookId: userBook["id"] as? Int,
                title: (editionTitle?.isEmpty == false ? editionTitle! : title).decodedHTMLEntities,
                author: author ?? NSLocalizedString("Unknown Author", comment: ""),
                rating: userBook["rating"] as? Double, finishedAt: date,
                coverImageData: nil, coverImageUrl: image)
        }
        return LibraryHistoryPage(entries: entries, nextOffset: offset + min(limit, rows.count), hasMore: rows.count > limit)
    }
}
