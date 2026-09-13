import Foundation

struct Quote: Identifiable, Codable {
    let id: Int
    let entry: String
    let bookId: Int
    let createdAt: String
    let bookTitle: String
    let authorName: String
    let editionId: Int?
    let privacySettingId: Int?
    let page: Int?

    static func decodeBookResponse(_ data: Data, bookID: Int) throws -> [Quote] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root["data"] as? [String: Any],
              let rows = value["user_books"] as? [[String: Any]] else { throw HardcoverNetworkError.invalidResponse }
        return try rows.flatMap { row -> [Quote] in
            guard let book = row["book"] as? [String: Any], let title = book["title"] as? String,
                  let journals = row["reading_journals"] as? [[String: Any]] else { throw HardcoverNetworkError.invalidResponse }
            return try journals.map { journal in
                guard let id = journal["id"] as? Int, let entry = journal["entry"] as? String else {
                    throw HardcoverNetworkError.invalidResponse
                }
                let metadata = journal["metadata"] as? [String: Any]
                let position = metadata?["position"] as? [String: Any]
                return Quote(id: id, entry: entry, bookId: bookID, createdAt: journal["created_at"] as? String ?? "",
                    bookTitle: title, authorName: "", editionId: journal["edition_id"] as? Int,
                    privacySettingId: journal["privacy_setting_id"] as? Int,
                    page: position?["value"] as? Int ?? metadata?["page"] as? Int)
            }
        }
    }
}
