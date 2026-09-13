import Foundation

// MARK: - GraphQL Models
struct GraphQLMeResponse: Codable {
    let data: MeData?
    let errors: [GraphQLError]?

    enum CodingKeys: String, CodingKey { case data, errors }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try c.decodeIfPresent(MeData.self, forKey: .data)
        self.errors = try c.decodeIfPresent([GraphQLError].self, forKey: .errors)
    }
}

struct GraphQLUserBooksResponse: Codable {
    let data: UserBooksData?
    let errors: [GraphQLError]?
}

struct GraphQLEditionsResponse: Codable {
    let data: EditionsData?
    let errors: [GraphQLError]?
}

struct GraphQLUpdateEditionResponse: Codable {
    let data: UpdateEditionData?
    let errors: [GraphQLError]?
}

struct GraphQLError: Codable {
    let message: String
}

struct MeData: Codable {
    let me: [MeUser]?
}

struct MeUser: Codable {
    let id: Int
    let username: String
}

struct UserBooksData: Codable {
    let user_books: [UserBook]?
}

struct EditionsData: Codable {
    let editions: [Edition]?
}

struct UpdateEditionData: Codable {
    let update_user_books: UpdateUserBooksResult?
}

struct UpdateUserBooksResult: Codable {
    let affected_rows: Int
}

struct UserBook: Codable {
    let id: Int?
    let bookId: Int?
    let statusId: Int?
    let editionId: Int?
    let privacySettingId: Int?
    let rating: Double?
    let updatedAt: String?
    let userBookReads: [UserBookRead]?
    let book: UserBookBook?
    let edition: Edition?

    enum CodingKeys: String, CodingKey {
        case id
        case bookId = "book_id"
        case statusId = "status_id"
        case editionId = "edition_id"
        case privacySettingId = "privacy_setting_id"
        case rating
        case updatedAt = "updated_at"
        case userBookReads = "user_book_reads"
        case book
        case edition
    }
}

struct UserBookRead: Codable {
    let id: Int?
    let startedAt: String?
    let finishedAt: String?
    let progressPages: Int?
    let progressSeconds: Int?
    let editionId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case progressPages = "progress_pages"
        case progressSeconds = "progress_seconds"
        case editionId = "edition_id"
    }
}

struct UserBookBook: Codable {
    let id: Int?
    let title: String
    let contributions: [BookContribution]?
    let image: BookImage?
    let editions: [Edition]? // include editions for release dates
    let rating: Double?
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, image, editions, rating
        case releaseDate = "release_date"
        case contributions = "cached_contributors"
    }
}

struct BookImage: Codable {
    let url: String?
}

struct BookContribution: Codable {
    let author: BookAuthor?
}

struct BookAuthor: Codable {
    let name: String?
}

struct Edition: Codable, Identifiable {
    let id: Int
    let title: String?
    let isbn10: String?
    let isbn13: String?
    let asin: String?
    let pages: Int?
    let audioSeconds: Int?
    let publisher: Publisher?
    let image: EditionImage?
    let releaseDate: String? // release_date (date)
    let readingFormat: EditionReadingFormat?
    var language: EditionLanguage? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isbn10 = "isbn_10"
        case isbn13 = "isbn_13"
        case asin
        case pages
        case audioSeconds = "audio_seconds"
        case publisher
        case image
        case releaseDate = "release_date"
        case readingFormat = "reading_format"
        case language
    }

    var displayTitle: String {
        return title ?? "Unknown Edition"
    }

    var displayFormat: String {
        guard let format = readingFormat?.format?.trimmingCharacters(in: .whitespacesAndNewlines),
              !format.isEmpty else {
            return NSLocalizedString("Unknown format", comment: "Edition has no reading format")
        }
        switch format.lowercased() {
        case "ebook", "e-book":
            return NSLocalizedString("E-book", comment: "Electronic book reading format")
        case "physical", "physical book":
            return NSLocalizedString("Physical book", comment: "Printed book reading format")
        case "audio", "audiobook", "audio book":
            return NSLocalizedString("Audiobook", comment: "Audio reading format")
        default:
            return format
        }
    }

    var isAudiobook: Bool {
        if let format = readingFormat?.format?.lowercased() {
            return ["audio", "audiobook", "audio book"].contains(format)
        }
        return (audioSeconds ?? 0) > 0
    }

    var totalMinutes: Int {
        guard let seconds = audioSeconds else { return 0 }
        return seconds / 60
    }

    var totalUnits: Int {
        return isAudiobook ? totalMinutes : (pages ?? 0)
    }

    var displayInfo: String {
        var info: [String] = []
        if let code = language?.code2, let name = Locale.current.localizedString(forLanguageCode: code) {
            info.append(name.localizedCapitalized)
        } else if let language = language?.language { info.append(language) }
        if let pub = publisher?.name {
            info.append(pub)
        }
        if let releaseDate, ReleaseDate.parse(releaseDate) != nil { info.append(String(releaseDate.prefix(4))) }
        if isAudiobook {
            let minutes = totalMinutes
            if minutes > 0 {
                let hours = minutes / 60
                let mins = minutes % 60
                if hours > 0 {
                    info.append("\(hours)h \(mins)m")
                } else {
                    info.append("\(mins)m")
                }
            }
        } else if let pageCount = pages {
            info.append(String(format: NSLocalizedString("%d pages", comment: "Edition page count"), pageCount))
        }
        return info.joined(separator: " • ")
    }
}

struct EditionReadingFormat: Codable {
    let format: String?
}

struct EditionLanguage: Codable {
    let code2: String?
    let language: String
}

struct Publisher: Codable {
    let id: Int?
    let name: String?
}

struct EditionImage: Codable {
    let url: String?
}

// MARK: - Goal Activity GraphQL Models
struct GraphQLActivitiesResponse: Codable {
    let data: ActivitiesData?
    let errors: [GraphQLError]?
}

struct ActivitiesData: Codable {
    let activities: [Activity]?
}

struct Activity: Codable {
    let id: Int?
    let event: String
    let data: ActivityData?
    let created_at: String?

    enum CodingKeys: String, CodingKey {
        case id, event, data
        case created_at = "created_at"
    }
}

struct ActivityData: Codable {
    let goal: ReadingGoal?
}

// Robust decoding for both camelCase and snake_case, and string/number coercion.
struct ReadingGoal: Codable, Sendable {
    let id: Int
    let goal: Int
    let metric: String
    let endDate: String
    let progress: Int
    let startDate: String
    let conditions: [String: String]?
    let description: String?
    let percentComplete: Double
    let privacySettingId: Int
    let archived: Bool

    init(
        id: Int,
        goal: Int,
        metric: String,
        endDate: String,
        progress: Int,
        startDate: String,
        conditions: [String: String]?,
        description: String?,
        percentComplete: Double,
        privacySettingId: Int,
        archived: Bool = false
    ) {
        self.id = id
        self.goal = goal
        self.metric = metric
        self.endDate = endDate
        self.progress = progress
        self.startDate = startDate
        self.conditions = conditions
        self.description = description
        self.percentComplete = percentComplete
        self.privacySettingId = privacySettingId
        self.archived = archived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicCodingKey.self)

        func intValue(_ keys: [String], default def: Int? = nil) throws -> Int {
            for k in keys {
                if let v = try? c.decode(Int.self, forKey: DynamicCodingKey(k)) { return v }
                if let s = try? c.decode(String.self, forKey: DynamicCodingKey(k)) {
                    // Try Int first (for "13"), then Double (for "13.0")
                    if let v = Int(s) { return v }
                    if let d = Double(s) { return Int(d) }
                }
                if let d = try? c.decode(Double.self, forKey: DynamicCodingKey(k)) { return Int(d) }
            }
            if let def = def { return def }
            throw DecodingError.keyNotFound(DynamicCodingKey(keys.first ?? "unknown"), .init(codingPath: decoder.codingPath, debugDescription: "Missing int for keys \(keys)"))
        }
        func doubleValue(_ keys: [String], default def: Double? = nil) throws -> Double {
            for k in keys {
                if let v = try? c.decode(Double.self, forKey: DynamicCodingKey(k)) { return v }
                if let i = try? c.decode(Int.self, forKey: DynamicCodingKey(k)) { return Double(i) }
                if let s = try? c.decode(String.self, forKey: DynamicCodingKey(k)), let v = Double(s) { return v }
            }
            if let def = def { return def }
            throw DecodingError.keyNotFound(DynamicCodingKey(keys.first ?? "unknown"), .init(codingPath: decoder.codingPath, debugDescription: "Missing double for keys \(keys)"))
        }
        func stringValue(_ keys: [String], default def: String? = nil) throws -> String {
            for k in keys {
                if let v = try? c.decode(String.self, forKey: DynamicCodingKey(k)), !v.isEmpty { return v }
                if let i = try? c.decode(Int.self, forKey: DynamicCodingKey(k)) { return String(i) }
                if let d = try? c.decode(Double.self, forKey: DynamicCodingKey(k)) { return String(d) }
            }
            if let def = def { return def }
            throw DecodingError.keyNotFound(DynamicCodingKey(keys.first ?? "unknown"), .init(codingPath: decoder.codingPath, debugDescription: "Missing string for keys \(keys)"))
        }
        func dictStringString(_ keys: [String]) -> [String: String]? {
            for k in keys {
                if let v = try? c.decode([String: String].self, forKey: DynamicCodingKey(k)) { return v }
            }
            return nil
        }
        func optionalString(_ keys: [String]) -> String? {
            for k in keys {
                if let v = try? c.decode(String.self, forKey: DynamicCodingKey(k)) { return v }
            }
            return nil
        }

        let id = try intValue(["id"])
        let goal = try intValue(["goal"])
        let metric = try stringValue(["metric"])
        let startDate = try stringValue(["startDate", "start_date"])
        let endDate = try stringValue(["endDate", "end_date"])

        // Progress can be Int, Double, or String (from HTML scraping)
        let progress = try intValue(["progress"], default: 0)

        let description = optionalString(["description", "name", "title"])
        let conditions = dictStringString(["conditions"])
        let privacy = (try? intValue(["privacySettingId", "privacy_setting_id"])) ?? 1

        // Try calculatedProgress (HTML scraping) or percentComplete (GraphQL) or compute fallback
        // HTML returns calculatedProgress as 0-100, GraphQL returns percentComplete as 0-1
        let percent: Double
        if let calc = try? doubleValue(["calculatedProgress", "calculated_progress"]) {
            // HTML scraping: 0-100 scale
            percent = min(1.0, max(0.0, calc / 100.0))
        } else if let p = try? doubleValue(["percentComplete", "percent_complete"]) {
            // GraphQL: 0-1 scale
            percent = min(1.0, max(0.0, p))
        } else {
            // Fallback: compute from progress/goal
            let denom = max(1, goal)
            percent = min(1.0, max(0.0, Double(progress) / Double(denom)))
        }

        // Check if archived (default to false for backward compatibility)
        let archived = (try? c.decode(Bool.self, forKey: DynamicCodingKey("archived"))) ?? false

        self.init(
            id: id,
            goal: goal,
            metric: metric,
            endDate: endDate,
            progress: progress,
            startDate: startDate,
            conditions: conditions,
            description: description,
            percentComplete: percent,
            privacySettingId: privacy,
            archived: archived
        )
    }
}

// Helper to read arbitrary keys
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { self.stringValue = string; self.intValue = nil }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

// MARK: - Search GraphQL Models
struct GraphQLSearchResponse: Decodable {
    let data: SearchData?
    let errors: [GraphQLError]?
}

struct SearchData: Decodable {
    let search: SearchResult?
}

struct SearchResult: Decodable {
    let ids: [Int]?
    let results: [SearchBookResult]?

    enum CodingKeys: String, CodingKey {
        case ids
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intIds = try? container.decode([Int].self, forKey: .ids) {
            ids = intIds
        } else if let stringIds = try? container.decode([String].self, forKey: .ids) {
            ids = stringIds.compactMap(Int.init)
        } else {
            ids = nil
        }
        results = try? container.decode([SearchBookResult].self, forKey: .results)
    }
}

struct SearchBookResult: Decodable {
    let id: Int
    let title: String
    let authorNames: [String]
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case authorNames = "author_names"
        case image
        case cachedImage = "cached_image"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = intId
        } else if let stringId = try? container.decode(String.self, forKey: .id),
                  let intId = Int(stringId) {
            id = intId
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Expected numeric book id")
        }

        let rawTitle = (try? container.decode(String.self, forKey: .title)) ?? "Unknown Title"
        title = rawTitle.decodedHTMLEntities
        authorNames = (try? container.decode([String].self, forKey: .authorNames)) ?? []

        if let image = try? container.decode(SearchResultImage.self, forKey: .image) {
            imageUrl = image.url
        } else if let cachedImage = try? container.decode(SearchResultImage.self, forKey: .cachedImage) {
            imageUrl = cachedImage.url
        } else if let image = try? container.decode(String.self, forKey: .image), !image.isEmpty {
            imageUrl = image
        } else {
            imageUrl = nil
        }
    }

    var hydratedBook: HydratedBook {
        let authorName = authorNames.first
        return HydratedBook(id: id, title: title, authorName: authorName, imageUrl: imageUrl)
    }
}

struct SearchResultImage: Decodable {
    let url: String?
}

struct GraphQLBooksHydrateResponse: Codable {
    let data: BooksHydrateData?
    let errors: [GraphQLError]?
}

struct BooksHydrateData: Codable {
    let books: [HydratedBook]?
}

struct HydratedBook: Codable, Identifiable {
    let id: Int
    let title: String
    let contributions: [BookContribution]?
    let image: BookImage?

    init(id: Int, title: String, authorName: String?, imageUrl: String?) {
        self.id = id
        self.title = title.decodedHTMLEntities
        if let authorName, !authorName.isEmpty {
            self.contributions = [BookContribution(author: BookAuthor(name: authorName))]
        } else {
            self.contributions = nil
        }
        if let imageUrl, !imageUrl.isEmpty {
            self.image = BookImage(url: imageUrl)
        } else {
            self.image = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, image
        case contributions = "cached_contributors"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        let rawTitle = try container.decode(String.self, forKey: .title)
        title = rawTitle.decodedHTMLEntities
        contributions = try container.decodeIfPresent([BookContribution].self, forKey: .contributions)
        image = try container.decodeIfPresent(BookImage.self, forKey: .image)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(contributions, forKey: .contributions)
        try container.encodeIfPresent(image, forKey: .image)
    }
}

// MARK: - Image Cache
