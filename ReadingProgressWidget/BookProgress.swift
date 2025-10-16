import Foundation

// This is now the only place where the "recipe" for BookProgress exists.
struct BookProgress: Identifiable {
    let id: String
    var title: String
    var author: String
    var coverImageData: Data?
    var coverImageUrl: String? // URL for async loading if coverImageData is nil
    var progress: Double = 0.0
    var totalPages: Int = 0
    var currentPage: Int = 0
    var bookId: Int? // For linking with book data
    var userBookId: Int? // For updating user's book settings
    var editionId: Int? // Current edition ID
    var originalTitle: String // Original book title (not edition specific)
    // Optional average rating for the current edition (0…5), if available from API.
    var editionAverageRating: Double? = nil
    // Your own rating on this user_book (0…5 in 0.5 steps), if set.
    var userRating: Double? = nil
    // NEW: Book description from the Books schema (string).
    var bookDescription: String? = nil
    // NEW: Release date for filtering upcoming/recent releases
    var releaseDate: String? = nil
}

