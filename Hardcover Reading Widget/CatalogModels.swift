import Foundation

enum CatalogError: LocalizedError {
    case message(String)
    case permission
    case accountChanged
    case locked
    case conflict
    case invalidResponse
    case rateLimited(Date)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .permission: return NSLocalizedString("Catalog editing requires a Hardcover librarian account.", comment: "")
        case .accountChanged: return NSLocalizedString("Your account changed. Close the editor and open it again.", comment: "")
        case .locked: return NSLocalizedString("This catalog record is locked on Hardcover.", comment: "")
        case .conflict: return NSLocalizedString("This record changed on Hardcover while you were editing. Reopen the editor to load the latest version.", comment: "")
        case .invalidResponse: return NSLocalizedString("Hardcover returned an unexpected response. No save could be confirmed.", comment: "")
        case .rateLimited(let date):
            return String(format: NSLocalizedString("Hardcover is temporarily limiting requests. Try again after %@.", comment: ""),
                          date.formatted(date: .abbreviated, time: .standard))
        }
    }
}

struct CatalogRoles: Decodable {
    let canEdit: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let allowed: Set<String> = ["librarian", "hardcover_admin"]
        // The roles field is JSON, not public profile flair. Unknown shapes fail closed.
        if let roles = try? container.decode([String].self) {
            canEdit = !allowed.isDisjoint(with: roles)
        } else if let roles = try? container.decode([String: Bool].self) {
            canEdit = roles.contains { allowed.contains($0.key) && $0.value }
        } else {
            canEdit = false
        }
    }
}

struct CatalogImage: Decodable, Equatable, Identifiable {
    let id: Int
    let url: String?
}

struct CatalogEntity: Decodable, Equatable, Identifiable {
    let id: Int
    let name: String?
    var displayName: String { name ?? "#\(id)" }
}

struct CatalogContribution: Decodable, Equatable, Identifiable {
    let id: Int
    let authorID: Int
    let author: CatalogEntity?
    let contribution: String?
    let roleID: Int?
    let specializationID: Int?
}

struct CatalogSeries: Decodable, Equatable, Identifiable {
    let id: Int
    let seriesID: Int
    let series: CatalogEntity?
    let position: Double?
    let details: String?
    let featured: Bool
    let compilation: Bool
}

struct CatalogBook: Decodable, Equatable, Identifiable {
    let id: Int
    let title: String?
    let description: String?
    let releaseDate: String?
    let locked: Bool
    let image: CatalogImage?
    let defaultCoverEditionID: Int?
    let defaultCoverEdition: CatalogEditionSummary?
    let series: [CatalogSeries]
    let contributions: [CatalogContribution]
}

struct CatalogEditionSummary: Decodable, Equatable, Identifiable {
    let id: Int
    let title: String?
    let isbn13: String?
    let readingFormat: CatalogFormat?
    let image: CatalogImage?
}

struct CatalogEdition: Decodable, Equatable, Identifiable {
    let id: Int
    let bookID: Int
    let title: String?
    let subtitle: String?
    let isbn10: String?
    let isbn13: String?
    let pages: Int?
    let audioSeconds: Int?
    let releaseDate: String?
    let readingFormatID: Int
    let editionFormat: String?
    let publisher: CatalogEntity?
    let image: CatalogImage?
    let images: [CatalogImage]
    let contributions: [CatalogContribution]
    let locked: Bool
}

struct CatalogFormat: Decodable, Equatable, Identifiable {
    static let audiobookID = 2
    let id: Int
    let format: String

    var displayName: String {
        switch format.lowercased() {
        case "ebook", "e-book": return NSLocalizedString("E-book", comment: "")
        case "physical", "physical book": return NSLocalizedString("Physical book", comment: "")
        case "audio", "audiobook", "audio book": return NSLocalizedString("Audiobook", comment: "")
        default: return format
        }
    }
}

struct CatalogLookups: Decodable {
    let formats: [CatalogFormat]
    let roles: [CatalogEntity]

    private static let editionRoleNames = [
        "Author", "Illustrator", "Editor", "Translator", "Narrator",
        "Foreword", "Introduction", "Cover Artist", "Other"
    ]

    // Keep the full registry for existing data, but offer only Hardcover's edition editor roles.
    var editionContributorRoles: [CatalogEntity] {
        Self.editionRoleNames.compactMap { name in
            roles.first { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    var defaultContributorRoleID: Int? {
        roles.first { $0.name?.caseInsensitiveCompare("Author") == .orderedSame }?.id
    }
}

struct CatalogContributorDraft: Identifiable, Equatable {
    var id = UUID()
    var author: CatalogEntity
    var roleID: Int?
    var specializationID: Int?
    var contribution: String?

    var input: [String: Any] {
        ["author_id": author.id, "contributor_role_id": roleID as Any? ?? NSNull(),
         "contributor_specialization_id": specializationID as Any? ?? NSNull(),
         "contribution": contribution as Any? ?? NSNull()]
    }
}

struct CatalogSeriesDraft: Identifiable, Equatable {
    var id: Int { series.id }
    var series: CatalogEntity
    var position: String
    var details: String?
    var featured: Bool
    var compilation: Bool

    func input() throws -> [String: Any] {
        let number = try CatalogValidation.position(position)
        return ["series_id": series.id, "position": number as Any? ?? NSNull(),
                "details": details as Any? ?? NSNull(), "featured": featured, "compilation": compilation]
    }
}

struct CatalogBookDraft: Equatable {
    var title: String
    var description: String
    var releaseDate: String
    var coverEditionID: Int?
    var series: [CatalogSeriesDraft]

    init(_ book: CatalogBook) {
        title = book.title ?? ""
        description = book.description ?? ""
        releaseDate = book.releaseDate ?? ""
        coverEditionID = book.defaultCoverEditionID
        series = book.series.map {
            CatalogSeriesDraft(series: $0.series ?? CatalogEntity(id: $0.seriesID, name: nil),
                               position: $0.position.map { String($0) } ?? "", details: $0.details,
                               featured: $0.featured, compilation: $0.compilation)
        }
    }

    func patch(from book: CatalogBook) throws -> [String: Any] {
        let original = CatalogBookDraft(book)
        var dto: [String: Any] = [:]
        if title != original.title {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CatalogError.message(NSLocalizedString("A title is required.", comment: ""))
            }
            dto["title"] = title
        }
        if description != original.description { dto["description"] = CatalogValidation.nullable(description) }
        if releaseDate != original.releaseDate { dto["release_date"] = try CatalogValidation.date(releaseDate) }
        if series != original.series {
            guard Set(series.map(\.id)).count == series.count else { throw CatalogError.invalidResponse }
            dto["series"] = try series.map { try $0.input() }
        }
        var result: [String: Any] = [:]
        if !dto.isEmpty { result["dto"] = dto }
        if coverEditionID != original.coverEditionID {
            result["default_cover_edition_id"] = coverEditionID as Any? ?? NSNull()
        }
        return result
    }
}

struct CatalogEditionDraft: Equatable {
    var title: String
    var subtitle: String
    var isbn10: String
    var isbn13: String
    var pages: String
    var audioSeconds: String
    var releaseDate: String
    var readingFormatID: Int
    var editionFormat: String
    var publisher: CatalogEntity?
    var imageID: Int?
    var coverURL = ""
    var contributors: [CatalogContributorDraft]

    var isAudiobook: Bool { readingFormatID == CatalogFormat.audiobookID }

    init(_ edition: CatalogEdition) {
        title = edition.title ?? ""
        subtitle = edition.subtitle ?? ""
        isbn10 = edition.isbn10 ?? ""
        isbn13 = edition.isbn13 ?? ""
        pages = edition.pages.map(String.init) ?? ""
        audioSeconds = edition.audioSeconds.map(String.init) ?? ""
        releaseDate = edition.releaseDate ?? ""
        readingFormatID = edition.readingFormatID
        editionFormat = edition.editionFormat ?? ""
        publisher = edition.publisher
        imageID = edition.image?.id
        contributors = edition.contributions.map {
            CatalogContributorDraft(author: $0.author ?? CatalogEntity(id: $0.authorID, name: nil),
                                    roleID: $0.roleID, specializationID: $0.specializationID,
                                    contribution: $0.contribution)
        }
    }

    func patch(from edition: CatalogEdition) throws -> [String: Any] {
        var dto: [String: Any] = [:]
        if title != edition.title ?? "" {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CatalogError.message(NSLocalizedString("A title is required.", comment: ""))
            }
            dto["title"] = title
        }
        if subtitle != edition.subtitle ?? "" { dto["subtitle"] = CatalogValidation.nullable(subtitle) }
        if isbn10 != edition.isbn10 ?? "" { dto["isbn_10"] = try CatalogValidation.isbn(isbn10, length: 10) }
        if isbn13 != edition.isbn13 ?? "" { dto["isbn_13"] = try CatalogValidation.isbn(isbn13, length: 13) }
        if pages != edition.pages.map(String.init) ?? "" { dto["page_count"] = try CatalogValidation.integer(pages) }
        if isAudiobook, audioSeconds != edition.audioSeconds.map(String.init) ?? "" {
            dto["audio_seconds"] = try CatalogValidation.integer(audioSeconds)
        }
        if releaseDate != edition.releaseDate ?? "" { dto["release_date"] = try CatalogValidation.date(releaseDate) }
        if readingFormatID != edition.readingFormatID { dto["reading_format_id"] = readingFormatID }
        if editionFormat != edition.editionFormat ?? "" { dto["edition_format"] = CatalogValidation.nullable(editionFormat) }
        if publisher?.id != edition.publisher?.id { dto["publisher_id"] = publisher?.id as Any? ?? NSNull() }
        if imageID != edition.image?.id { dto["image_id"] = imageID as Any? ?? NSNull() }
        let inputs = contributors.map(\.input)
        let originalInputs = CatalogEditionDraft(edition).contributors.map(\.input)
        if !NSArray(array: inputs).isEqual(to: originalInputs) { dto["contributions"] = inputs }
        if !coverURL.isEmpty { _ = try CatalogValidation.coverURL(coverURL) }
        return dto.isEmpty ? [:] : ["dto": dto]
    }
}

enum CatalogValidation {
    static func nullable(_ value: String) -> Any { value.isEmpty ? NSNull() : value as Any }

    static func date(_ value: String) throws -> Any {
        if value.isEmpty { return NSNull() }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard value.count == 10, let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw CatalogError.message(NSLocalizedString("Enter a valid date as YYYY-MM-DD.", comment: ""))
        }
        return value
    }

    static func integer(_ value: String) throws -> Any {
        if value.isEmpty { return NSNull() }
        guard let number = Int(value), number >= 0, number <= Int32.max else {
            throw CatalogError.message(NSLocalizedString("Enter a non-negative whole number.", comment: ""))
        }
        return number
    }

    static func position(_ value: String) throws -> Double? {
        if value.isEmpty { return nil }
        guard let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite, number >= 0 else {
            throw CatalogError.message(NSLocalizedString("Enter a valid series position.", comment: ""))
        }
        return number
    }

    static func isbn(_ value: String, length: Int) throws -> Any {
        let cleaned = value.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").uppercased()
        if cleaned.isEmpty { return NSNull() }
        let digits = cleaned.map { $0 == "X" ? 10 : Int(String($0)) ?? -1 }
        var valid = digits.count == length && digits.allSatisfy { $0 >= 0 }
        if valid, length == 10 {
            valid = digits.prefix(9).allSatisfy { $0 < 10 } && zip(digits, stride(from: 10, through: 1, by: -1)).reduce(0) { $0 + $1.0 * $1.1 } % 11 == 0
        } else if valid, length == 13 {
            valid = digits.allSatisfy { $0 < 10 } && digits.enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 1 : 3) } % 10 == 0
        }
        guard valid else { throw CatalogError.message(NSLocalizedString("The ISBN is invalid. Check its digits and checksum.", comment: "")) }
        return cleaned
    }

    static func coverURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw CatalogError.message(NSLocalizedString("Enter a public HTTPS image URL without login details.", comment: ""))
        }
        return url
    }
}
