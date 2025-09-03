import Foundation

// This is now the only place where the "recipe" for BookProgress exists.
struct BookProgress: Identifiable {
    let id: String
    var title: String
    var author: String
    var coverImageData: Data?
    var progress: Double = 0.0
    var totalPages: Int = 0
    var currentPage: Int = 0
    var bookId: Int? // For linking with book data
    var userBookId: Int? // For updating user's book settings
    var editionId: Int? // Current edition ID
    var originalTitle: String // Original book title (not edition specific)
}
