import Foundation

struct FinishedBookEntry: Identifiable, Hashable {
    let id: Int                 // read row id
    let bookId: Int             // underlying book id
    let userBookId: Int?        // user_book id (for potential drill-in)
    let title: String
    let author: String
    let rating: Double?         // 0.5–5.0
    let finishedAt: Date
    let coverImageData: Data?
    let coverImageUrl: String?
}
