import Foundation

enum HardcoverReadingFormat {
    static func displayName(for rawValue: String?, assumeAudiobook: Bool = false) -> String {
        if assumeAudiobook {
            return NSLocalizedString("Audiobook", comment: "Audio reading format")
        }

        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch value.lowercased() {
        case "ebook", "e-book":
            return NSLocalizedString("E-book", comment: "Electronic book reading format")
        case "read", "physical", "physical book":
            return NSLocalizedString("Physical book", comment: "Printed book reading format")
        case "listened", "audio", "audiobook", "audio book":
            return NSLocalizedString("Audiobook", comment: "Audio reading format")
        default:
            return value.isEmpty ? NSLocalizedString("Unknown format", comment: "Edition has no reading format") : value
        }
    }

    static func isAudiobook(_ rawValue: String?) -> Bool {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["listened", "audio", "audiobook", "audio book"].contains(value)
    }
}

// This is now the only place where the "recipe" for BookProgress exists.
struct BookProgress: Identifiable, Codable, Hashable, Sendable {
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
    // NEW: Audiobook support
    var isAudiobook: Bool = false
    var totalMinutes: Int = 0
    var currentMinute: Int = 0
    var readingFormat: String? = nil
    var statusId: Int? = nil
    var parsedReleaseDate: Date? = nil

    var currentUnits: Int { isAudiobook ? currentMinute : currentPage }
    var totalUnits: Int { isAudiobook ? totalMinutes : totalPages }
    var displayFormat: String {
        HardcoverReadingFormat.displayName(for: readingFormat, assumeAudiobook: isAudiobook)
    }

    func withProgress(_ units: Int) -> BookProgress {
        var updated = self
        let value = max(0, totalUnits > 0 ? min(units, totalUnits) : units)
        if isAudiobook { updated.currentMinute = value } else { updated.currentPage = value }
        updated.progress = totalUnits > 0 ? Double(value) / Double(totalUnits) : 0
        return updated
    }
    
    var progressText: String {
        if isAudiobook {
            let currentHours = currentMinute / 60
            let currentMins = currentMinute % 60
            let totalHours = totalMinutes / 60
            let totalMins = totalMinutes % 60
            
            if totalHours > 0 {
                return "\(currentHours)h \(currentMins)m of \(totalHours)h \(totalMins)m"
            } else {
                return "\(currentMins)m of \(totalMins)m"
            }
        } else {
            return "Page \(currentPage) of \(totalPages)"
        }
    }
}
