import Foundation
import UIKit
import ImageIO
import MobileCoreServices

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
    let editionId: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case progressPages = "progress_pages"
        case editionId = "edition_id"
    }
}

struct UserBookBook: Codable {
    let id: Int?
    let title: String
    let contributions: [BookContribution]?
    let image: BookImage?
    let editions: [Edition]? // include editions for release dates
    
    enum CodingKeys: String, CodingKey {
        case id, title, contributions, image, editions
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
    let pages: Int?
    let publisher: Publisher?
    let image: EditionImage?
    let releaseDate: String? // release_date (date)
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isbn10 = "isbn_10"
        case isbn13 = "isbn_13"
        case pages
        case publisher
        case image
        case releaseDate = "release_date"
    }
    
    var displayTitle: String {
        return title ?? "Unknown Edition"
    }
    
    var displayInfo: String {
        var info: [String] = []
        if let pub = publisher?.name {
            info.append(pub)
        }
        if let pageCount = pages {
            info.append("\(pageCount) pages")
        }
        return info.joined(separator: " • ")
    }
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
struct ReadingGoal: Codable {
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
        privacySettingId: Int
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
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicCodingKey.self)
        
        func intValue(_ keys: [String], default def: Int? = nil) throws -> Int {
            for k in keys {
                if let v = try? c.decode(Int.self, forKey: DynamicCodingKey(k)) { return v }
                if let s = try? c.decode(String.self, forKey: DynamicCodingKey(k)), let v = Int(s) { return v }
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
        let progress = try intValue(["progress"], default: 0)
        let description = optionalString(["description", "name", "title"])
        let conditions = dictStringString(["conditions"])
        let privacy = (try? intValue(["privacySettingId", "privacy_setting_id"])) ?? 1
        
        // percentComplete may be missing or snake_case or string – compute fallback
        let percent: Double
        if let p = try? doubleValue(["percentComplete", "percent_complete"]) {
            percent = min(1.0, max(0.0, p))
        } else {
            let denom = max(1, goal)
            percent = min(1.0, max(0.0, Double(progress) / Double(denom)))
        }
        
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
            privacySettingId: privacy
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
struct GraphQLSearchResponse: Codable {
    let data: SearchData?
    let errors: [GraphQLError]?
}

struct SearchData: Codable {
    let search: SearchResult?
}

struct SearchResult: Codable {
    let ids: [String]?
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
    
    enum CodingKeys: String, CodingKey {
        case id, title, contributions, image
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
class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSData>()
    
    private init() {
        // Conservative cache limits for widget extension
        cache.countLimit = 8
        cache.totalCostLimit = 3 * 1024 * 1024 // ~3MB
    }
    
    func setImageData(_ data: Data, forKey key: String) {
        cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
    }
    func imageData(forKey key: String) -> Data? {
        return cache.object(forKey: key as NSString) as Data?
    }
}

extension ImageCache {
    func clearCache() {
        cache.removeAllObjects()
    }
}

// MARK: - Configuration
struct HardcoverConfig {
    private static var rawApiKey: String {
        if let key = AppGroup.defaults.string(forKey: "HardcoverAPIKey"), !key.isEmpty {
            return key
        }
        return ""
    }
    static var apiKey: String { normalize(rawApiKey) }
    static var authorizationHeaderValue: String { headerValue(for: rawApiKey) }
    static func normalize(_ key: String) -> String {
        var k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = k.lowercased()
        if lower.hasPrefix("authorization:") {
            k = String(k.dropFirst("authorization:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if k.lowercased().hasPrefix("bearer ") {
            k = String(k.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if k.hasPrefix("\""), k.hasSuffix("\""), k.count >= 2 {
            k = String(k.dropFirst().dropLast())
        }
        return k
    }
    static func headerValue(for key: String) -> String {
        let normalized = normalize(key)
        guard !normalized.isEmpty else { return "" }
        return "Bearer \(normalized)"
    }
    static var username: String {
        if let u = AppGroup.defaults.string(forKey: "HardcoverUsername"), !u.isEmpty {
            return normalizeUsername(u)
        }
        return ""
    }
    static func normalizeUsername(_ username: String) -> String {
        var u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.hasPrefix("@") { u = String(u.dropFirst()) }
        return u
    }
}

// MARK: - Service
class HardcoverService {
  
  static func fetchCurrentlyReading() async -> [BookProgress] {
      guard !HardcoverConfig.apiKey.isEmpty else {
          print("❌ No API key configured")
          return []
      }
      let books = await fetchBooksFromGraphQL(apiKey: HardcoverConfig.apiKey)
      ImageCache.shared.clearCache()
      return books
  }
  
  // NEW: Fetch Want to Read list (status_id = 1)
  static func fetchWantToRead(limit: Int) async -> [BookProgress] {
      guard !HardcoverConfig.apiKey.isEmpty else { return [] }
      guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { return [] }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
      
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let query = """
      query ($userId: Int!, $limit: Int!) {
        user_books(
          where: { user_id: { _eq: $userId }, status_id: { _eq: 1 } },
          order_by: { id: desc },
          limit: $limit
        ) {
          id
          book_id
          status_id
          edition_id
          rating
          book {
            id
            title
            contributions { author { name } }
            image { url }
          }
          edition {
            id
            title
            pages
            image { url }
            release_date
          }
        }
      }
      """
      let body: [String: Any] = [
          "query": query,
          "variables": ["userId": userId, "limit": max(1, limit)]
      ]
      
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await URLSession.shared.data(for: request)
          let resp = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data)
          if let errs = resp.errors, !errs.isEmpty { return [] }
          guard let rows = resp.data?.user_books else { return [] }
          
          var items: [BookProgress] = []
          items.reserveCapacity(rows.count)
          
          for ub in rows {
              guard let bookData = ub.book else { continue }
              
              // Title preference: edition title if present, else book title
              let rawTitle = (ub.edition?.title?.isEmpty == false) ? ub.edition!.title! : bookData.title
              let displayTitle = rawTitle.decodedHTMLEntities
              let author = bookData.contributions?.first?.author?.name ?? "Unknown Author"
              
              // Prefer edition image, else book image
              var imageUrl: String? = nil
              if let u = ub.edition?.image?.url, !u.isEmpty { imageUrl = u }
              else if let u = bookData.image?.url, !u.isEmpty { imageUrl = u }
              
              let coverData: Data? = (imageUrl != nil) ? await fetchAndResizeImage(from: imageUrl!) : nil
              
              let totalPages = ub.edition?.pages ?? 0
              let releaseDate = ub.edition?.releaseDate
              
              let item = BookProgress(
                  id: "\(ub.id ?? 0)",
                  title: displayTitle,
                  author: author,
                  coverImageData: coverData,
                  progress: 0.0,
                  totalPages: totalPages,
                  currentPage: 0,
                  bookId: bookData.id,
                  userBookId: ub.id,
                  editionId: ub.editionId,
                  originalTitle: bookData.title.decodedHTMLEntities,
                  releaseDate: releaseDate
              )
              items.append(item)
          }
          
          return items
      } catch {
          return []
      }
  }
  
  static func refreshUsernameFromAPI() async {
      guard !HardcoverConfig.apiKey.isEmpty else {
          AppGroup.defaults.set("", forKey: "HardcoverUsername")
          return
      }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      let query = """
      { "query": "{ me { id username } }" }
      """
      request.httpBody = query.data(using: .utf8)
      do {
          let (data, _) = try await URLSession.shared.data(for: request)
          let gqlResponse = try JSONDecoder().decode(GraphQLMeResponse.self, from: data)
          if let errors = gqlResponse.errors, !errors.isEmpty {
              AppGroup.defaults.set("", forKey: "HardcoverUsername")
              return
          }
          if let meUsers = gqlResponse.data?.me, let currentUser = meUsers.first {
              let normalized = HardcoverConfig.normalizeUsername(currentUser.username)
              AppGroup.defaults.set(normalized, forKey: "HardcoverUsername")
          } else {
              AppGroup.defaults.set("", forKey: "HardcoverUsername")
          }
      } catch {
          AppGroup.defaults.set("", forKey: "HardcoverUsername")
      }
  }
  
  private static func fetchUserId(apiKey: String) async -> Int? {
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.headerValue(for: apiKey), forHTTPHeaderField: "Authorization")
      let query = """
      { "query": "{ me { id username } }" }
      """
      request.httpBody = query.data(using: .utf8)
      do {
          let (data, _) = try await URLSession.shared.data(for: request)
          let gqlResponse = try JSONDecoder().decode(GraphQLMeResponse.self, from: data)
          if let errors = gqlResponse.errors, !errors.isEmpty {
              errors.forEach { print("❌ GraphQL User API Error: \($0.message)") }
              return nil
          }
          guard let meUsers = gqlResponse.data?.me, let currentUser = meUsers.first else { return nil }
          return currentUser.id
      } catch {
          print("❌ GraphQL User API Error: \(error)")
          return nil
      }
  }
  
  private static func fetchAndResizeImage(from urlString: String) async -> Data? {
      guard let url = URL(string: urlString) else { return nil }
      if let cached = ImageCache.shared.imageData(forKey: urlString) { return cached }
      do {
          let (data, _) = try await URLSession.shared.data(from: url)
          let resized = autoreleasepool(invoking: { () -> Data? in
              return resizeImageToFitWidget(data)
          })
          if let resized {
              ImageCache.shared.setImageData(resized, forKey: urlString)
              return resized
          }
          return nil
      } catch {
          print("❌ Image download error: \(error)")
          return nil
      }
  }
  
  // Downsample with ImageIO to avoid decoding the full-size image in memory.
  private static func resizeImageToFitWidget(_ imageData: Data) -> Data? {
      let targetMaxPixel: CGFloat = 360 // pixels on the longest side - increased for better quality
      let compression: CGFloat = 0.8 // slightly higher quality compression
      
      guard let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
          return nil
      }
      let options: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceShouldCache: false,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: Int(targetMaxPixel)
      ]
      guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
          return nil
      }
      let ui = UIImage(cgImage: cgThumb, scale: 1.0, orientation: .up)
      return ui.jpegData(compressionQuality: compression)
  }
  
  private static func fetchBooksFromGraphQL(apiKey: String) async -> [BookProgress] {
      guard let userId = await fetchUserId(apiKey: apiKey) else {
          print("❌ Could not get user ID")
          return []
      }
      
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.headerValue(for: apiKey), forHTTPHeaderField: "Authorization")
      
      let booksQuery = """
      { "query": "{ user_books(where: {user_id: {_eq: \(userId)}, status_id: {_eq: 2}}, order_by: {id: desc}, limit: 10) { id book_id status_id edition_id privacy_setting_id rating user_book_reads(order_by: {id: asc}) { id started_at finished_at progress_pages edition_id } book { id title contributions { author { name } } image { url } } edition { id title isbn_10 isbn_13 pages publisher { name } image { url } } } }" }
      """
      request.httpBody = booksQuery.data(using: .utf8)
      
      do {
          let (data, _) = try await URLSession.shared.data(for: request)
          let gqlResponse = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data)
          if let errors = gqlResponse.errors {
              for error in errors {
                  print("❌ GraphQL Books API Error: \(error.message)")
              }
              return []
          }
          guard let userBooks = gqlResponse.data?.user_books else {
              print("❌ GraphQL API: No user books data returned")
              return []
          }
          print("✅ Successfully fetched \(userBooks.count) books from GraphQL")
          
          var books: [BookProgress] = []
          for userBook in userBooks {
              guard let bookData = userBook.book else { continue }
              let rawTitle: String
              if let editionTitle = userBook.edition?.title, !editionTitle.isEmpty {
                  rawTitle = editionTitle
              } else {
                  rawTitle = bookData.title
              }
              let displayTitle = rawTitle.decodedHTMLEntities
              let author = bookData.contributions?.first?.author?.name ?? "Unknown Author"
              let totalPages = userBook.edition?.pages ?? 0
              
              var currentPage = 0
              var progress = 0.0
              if let userBookReads = userBook.userBookReads, !userBookReads.isEmpty,
                 let latestRead = userBookReads.last,
                 let progressPages = latestRead.progressPages {
                  currentPage = progressPages
                  if totalPages > 0 {
                      progress = Double(progressPages) / Double(totalPages)
                  }
              }
              
              let imageUrl: String?
              if let editionImageUrl = userBook.edition?.image?.url, !editionImageUrl.isEmpty {
                  imageUrl = editionImageUrl
              } else if let bookImageUrl = bookData.image?.url, !bookImageUrl.isEmpty {
                  imageUrl = bookImageUrl
              } else {
                  imageUrl = nil
              }
              
              var coverImageData: Data? = nil
              if let imageUrl = imageUrl {
                  coverImageData = await fetchAndResizeImage(from: imageUrl)
              }
              
              let book = BookProgress(
                  id: "\(userBook.id ?? 0)",
                  title: displayTitle,
                  author: author,
                  coverImageData: coverImageData,
                  progress: progress,
                  totalPages: totalPages,
                  currentPage: currentPage, // FIX: använd beräknad currentPage
                  bookId: bookData.id,
                  userBookId: userBook.id,
                  editionId: userBook.editionId,
                  originalTitle: bookData.title.decodedHTMLEntities
              )
              
              books.append(book)
          }
          return books
      } catch {
          print("❌ GraphQL Books API Error: \(error)")
          return []
      }
  }
  
  static func fetchEditions(for bookId: Int) async -> [Edition] {
      guard !HardcoverConfig.apiKey.isEmpty else { return [] }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let query = """
      { "query": "{ editions(where: {book_id: {_eq: \(bookId)}, _or: [{reading_format_id: {_is_null: true}}, {reading_format_id: {_neq: 2}}]}, order_by: { users_count: desc_nulls_last }) { id title isbn_10 isbn_13 pages publisher { name } image { url } } }" }
      """
      request.httpBody = query.data(using: .utf8)
      
      do {
          let (data, _) = try await URLSession.shared.data(for: request)
          let gqlResponse = try JSONDecoder().decode(GraphQLEditionsResponse.self, from: data)
          if let errors = gqlResponse.errors {
              for error in errors {
                  print("❌ GraphQL Editions API Error: \(error.message)")
              }
              return []
          }
          return gqlResponse.data?.editions ?? []
      } catch {
          print("❌ GraphQL Editions API Error: \(error)")
          return []
      }
  }
  
  static func updateEdition(userBookId: Int, editionId: Int) async -> Bool {
    print("📝 Attempting to update edition - UserBookId: \(userBookId), EditionId: \(editionId)")
    guard !HardcoverConfig.apiKey.isEmpty else { return false }
    guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

    guard let ub = await fetchUserBook(by: userBookId), let bookId = ub.bookId else {
        print("❌ Could not fetch user_book or book_id for id=\(userBookId)")
        return false
    }
    let status = ub.statusId ?? 2
    let privacy: Int
    if let p = ub.privacySettingId { privacy = p } else { privacy = await fetchAccountPrivacySettingId() ?? 1 }

    let body: [String: Any] = [
        "query": """
        mutation InsertUserBook($object: UserBookCreateInput!) {
          insert_user_book(object: $object) {
            error
            user_book { id book_id edition_id status_id privacy_setting_id }
          }
        }
        """,
        "variables": [
            "object": [
                "book_id": bookId,
                "edition_id": editionId,
                "status_id": status,
                "privacy_setting_id": privacy
            ]
        ]
    ]

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse { print("📥 insert_user_book HTTP Status: \(http.statusCode)") }
        if let raw = String(data: data, encoding: .utf8) { print("📥 insert_user_book Raw: \(raw)") }
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ insert_user_book GraphQL errors: \(errs)")
                return false
            }
            if let dataDict = json["data"] as? [String: Any],
               let insert = dataDict["insert_user_book"] as? [String: Any] {
                if let err = insert["error"] as? String, !err.isEmpty {
                    print("❌ insert_user_book error: \(err)")
                    return false
                }
                _ = await updateLatestReadEdition(userBookId: userBookId, editionId: editionId)
                return insert["user_book"] != nil
            }
        }
        return false
    } catch {
        print("❌ updateEdition (insert_user_book) Error: \(error)")
        return false
    }
  }

  private static func updateLatestReadEdition(userBookId: Int, editionId: Int) async -> Bool {
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

      let readsQuery: [String: Any] = [
          "query": """
          query ($id: Int!) {
            user_book_reads(where: { user_book_id: { _eq: $id } }, order_by: { id: desc }, limit: 1) {
              id
            }
          }
          """,
          "variables": ["id": userBookId]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: readsQuery)
          let (data, _) = try await URLSession.shared.data(for: request)
          guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataDict = root["data"] as? [String: Any],
                let reads = dataDict["user_book_reads"] as? [[String: Any]],
                let latest = reads.first, let readId = latest["id"] as? Int else {
              return false
          }
          let updateQuery: [String: Any] = [
              "query": """
              mutation ($id: Int!, $edition: Int!) {
                update_user_book_read(id: $id, object: { edition_id: $edition }) {
                  error
                  user_book_read { id edition_id }
                }
              }
              """,
              "variables": ["id": readId, "edition": editionId]
          ]
          request.httpBody = try JSONSerialization.data(withJSONObject: updateQuery)
          let (uData, _) = try await URLSession.shared.data(for: request)
          if let root2 = try JSONSerialization.jsonObject(with: uData) as? [String: Any],
             let errs = root2["errors"] as? [[String: Any]], !errs.isEmpty {
              return false
          }
          return true
      } catch {
          print("❌ updateLatestReadEdition error: \(error)")
          return false
      }
  }
  
  static func insertBookRead(userBookId: Int, page: Int, editionId: Int? = nil) async -> Bool {
      print("📝 Updating book read progress - UserBookId: \(userBookId), Page: \(page), EditionId: \(editionId ?? -1)")
      guard !HardcoverConfig.apiKey.isEmpty else { 
          print("❌ API key is empty")
          return false 
      }
      guard page >= 0 else { 
          print("❌ Invalid page number: \(page)")
          return false 
      }
      
      // First, try to find the latest user_book_read for this user_book
      if let latestReadId = await fetchLatestReadId(userBookId: userBookId) {
          // Update the existing read
          print("📝 Updating existing read ID: \(latestReadId)")
          let success = await updateExistingBookRead(readId: latestReadId, page: page, editionId: editionId)
          if success {
              print("✅ Successfully updated existing read")
              return true
          }
          print("⚠️ Failed to update existing read, will try creating new one")
      } else {
          print("⚠️ No existing read found")
      }
      
      // If update failed or no existing read, create new one
      print("📝 Creating new book read")
      return await createNewBookRead(userBookId: userBookId, page: page, editionId: editionId)
  }
  
  private static func fetchLatestReadId(userBookId: Int) async -> Int? {
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let query = """
      query ($id: Int!) {
        user_book_reads(where: { user_book_id: { _eq: $id }, finished_at: { _is_null: true } }, order_by: { id: desc }, limit: 1) {
          id
          started_at
          finished_at
        }
      }
      """
      
      let body: [String: Any] = [
          "query": query,
          "variables": ["id": userBookId]
      ]
      
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await URLSession.shared.data(for: request)
          
          if let raw = String(data: data, encoding: .utf8) {
              print("📥 fetchLatestReadId response: \(raw)")
          }
          
          guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataDict = json["data"] as? [String: Any],
                let reads = dataDict["user_book_reads"] as? [[String: Any]],
                let latest = reads.first,
                let readId = latest["id"] as? Int else {
              print("⚠️ No ongoing read found (finished_at is null)")
              return nil
          }
          print("✅ Found ongoing read ID: \(readId)")
          return readId
      } catch {
          print("❌ fetchLatestReadId error: \(error)")
          return nil
      }
  }
  
  private static func updateExistingBookRead(readId: Int, page: Int, editionId: Int?) async -> Bool {
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      var datesReadDict: [String: Any] = ["progress_pages": page]
      if let eid = editionId {
          datesReadDict["edition_id"] = eid
      }
      
      let mutation = """
      mutation ($id: Int!, $object: DatesReadInput!) {
          update_user_book_read(id: $id, object: $object) {
              error
              user_book_read { id progress_pages edition_id }
          }
      }
      """
      
      let body: [String: Any] = [
          "query": mutation,
          "variables": [
              "id": readId,
              "object": datesReadDict
          ]
      ]
      
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, response) = try await URLSession.shared.data(for: request)
          if let http = response as? HTTPURLResponse { print("📥 Update user_book_read HTTP Status: \(http.statusCode)") }
          if let raw = String(data: data, encoding: .utf8) { print("📥 Update user_book_read Raw: \(raw)") }
          if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
              if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty {
                  print("❌ Update errors: \(errs)")
                  return false
              }
              if let dataDict = json["data"] as? [String: Any],
                 let update = dataDict["update_user_book_read"] as? [String: Any] {
                  if let err = update["error"] as? String, !err.isEmpty {
                      print("❌ Update error: \(err)")
                      return false
                  }
                  return update["user_book_read"] != nil
              }
          }
          return false
      } catch {
          print("❌ updateExistingBookRead error: \(error)")
          return false
      }
  }
  
  private static func createNewBookRead(userBookId: Int, page: Int, editionId: Int?) async -> Bool {
      guard !HardcoverConfig.apiKey.isEmpty else { return false }
      guard page >= 0 else { return false }
      
      var targetEditionId = editionId
      if targetEditionId == nil {
          if let userBook = await fetchUserBook(by: userBookId) {
              targetEditionId = userBook.editionId
          }
      }
      
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let df = DateFormatter()
      df.calendar = Calendar(identifier: .gregorian)
      df.locale = Locale(identifier: "en_US_POSIX")
      df.timeZone = TimeZone(secondsFromGMT: 0)
      df.dateFormat = "yyyy-MM-dd"
      let startedAt = df.string(from: Date())
      
      let mutation = """
      mutation InsertUserBookRead($id: Int!, $pages: Int, $editionId: Int, $startedAt: date) {
          insert_user_book_read(user_book_id: $id, user_book_read: {
              progress_pages: $pages,
              edition_id: $editionId,
              started_at: $startedAt,
          }) {
              error
              user_book_read { id progress_pages edition_id started_at finished_at }
          }
      }
      """
      var variables: [String: Any] = [
          "id": userBookId,
          "pages": page,
          "startedAt": startedAt
      ]
      if let eid = targetEditionId { variables["editionId"] = eid }
      
      let bodyDict: [String: Any] = [
          "query": mutation,
          "variables": variables
      ]
      
      do {
          let body = try JSONSerialization.data(withJSONObject: bodyDict)
          request.httpBody = body
          let (data, response) = try await URLSession.shared.data(for: request)
          if let http = response as? HTTPURLResponse { print("📥 Insert user_book_read HTTP Status: \(http.statusCode)") }
          if let raw = String(data: data, encoding: .utf8) { print("📥 Insert user_book_read Raw: \(raw)") }
          if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
              if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty {
                  return false
              }
              if let dataDict = json["data"] as? [String: Any],
                 let insert = dataDict["insert_user_book_read"] as? [String: Any] {
                  if let err = insert["error"] as? String, !err.isEmpty {
                      return false
                  }
                  return insert["user_book_read"] != nil
              }
          }
          return false
      } catch {
          print("❌ Insert user_book_read Error: \(error)")
          return false
      }
  }
  
  static func updateProgress(userBookId: Int, editionId: Int?, page: Int) async -> Bool {
      return await insertBookRead(userBookId: userBookId, page: page, editionId: editionId)
  }
  
  // MARK: - Search API
  static func searchBooks(title: String, author: String? = nil, page: Int = 1) async -> [HydratedBook] {
      guard !HardcoverConfig.apiKey.isEmpty else { return [] }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let q = (title + " " + (author ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !q.isEmpty else { return [] }
      
      let query = """
      query ($query: String!, $page: Int!) {
        search(query: $query, per_page: 25, page: $page, query_type: \"Book\") {
          ids
        }
      }
      """
      let body: [String: Any] = [
          "query": query,
          "variables": [
              "query": q,
              "page": page
          ]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await URLSession.shared.data(for: request)
          let resp = try JSONDecoder().decode(GraphQLSearchResponse.self, from: data)
          if let errors = resp.errors, !errors.isEmpty {
              errors.forEach { print("❌ GraphQL Search Error: \($0.message)") }
              return []
          }
          guard let idsStr = resp.data?.search?.ids else { return [] }
          let ids = idsStr.compactMap { Int($0) }
          guard !ids.isEmpty else { return [] }
          return await hydrateBooksByIds(ids)
      } catch {
          print("❌ GraphQL Search Error: \(error)")
          return []
      }
  }
  
  private static func hydrateBooksByIds(_ ids: [Int]) async -> [HydratedBook] {
      guard !HardcoverConfig.apiKey.isEmpty else { return [] }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let query = """
      query ($ids: [Int!]) {
        books(where: { id: { _in: $ids }}) {
          id
          title
          contributions { author { name } }
          image { url }
        }
      }
      """
      let body: [String: Any] = [
          "query": query,
          "variables": ["ids": ids]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await URLSession.shared.data(for: request)
          let resp = try JSONDecoder().decode(GraphQLBooksHydrateResponse.self, from: data)
          if let errors = resp.errors, !errors.isEmpty {
              errors.forEach { print("❌ GraphQL Hydrate Error: \($0.message)") }
              return []
          }
          let list = resp.data?.books ?? []
          if list.count > 1 {
              var order: [Int: Int] = [:]
              for (i, v) in ids.enumerated() { order[v] = i }
              return list.sorted { (a, b) -> Bool in
                  (order[a.id] ?? Int.max) < (order[b.id] ?? Int.max)
              }
          }
          return list
      } catch {
          print("❌ GraphQL Hydrate Error: \(error)")
          return []
      }
  }
  
  // MARK: - Add book to Currently Reading
  static func addBookToCurrentlyReading(bookId: Int, editionId: Int?) async -> Bool {
      guard !HardcoverConfig.apiKey.isEmpty else { return false }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

      let privacySetting = await fetchAccountPrivacySettingId() ?? 1

      var object: [String: Any] = [
          "book_id":  bookId,
          "status_id": 2,
          "privacy_setting_id": privacySetting
      ]
      if let eid = editionId { object["edition_id"] = eid }

      let body: [String: Any] = [
          "query": """
          mutation InsertUserBook($object: UserBookCreateInput!) {
            insert_user_book(object: $object) {
              error
              user_book { id book_id edition_id status_id privacy_setting_id }
            }
          }
          """,
          "variables": ["object": object]
      ]

      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, response) = try await URLSession.shared.data(for: request)
          if let http = response as? HTTPURLResponse { print("📥 Insert user_book HTTP Status: \(http.statusCode)") }
          if let raw = String(data: data, encoding: .utf8) { print("📥 Insert user_book Raw: \(raw)") }
          if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
              if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty {
                  print("❌ Insert user_book GraphQL errors: \(errs)")
                  return false
              }
              if let dataDict = json["data"] as? [String: Any],
                 let insert = dataDict["insert_user_book"] as? [String: Any] {
                  if let err = insert["error"] as? String, !err.isEmpty {
                      print("❌ Insert user_book error: \(err)")
                      return false
                  }
                  return insert["user_book"] != nil
              }
          }
          return false
      } catch {
          print("❌ Insert user_book Error: \(error)")
          return false
      }
  }
  
  static func updateUserBookStatus(userBookId: Int, statusId: Int) async -> Bool {
      guard !HardcoverConfig.apiKey.isEmpty else { return false }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      let body: [String: Any] = [
          "query": """
          mutation ($id: Int!, $status: Int) {
            update_user_book(id: $id, object: { status_id: $status }) {
              error
              user_book { id status_id }
            }
          }
          """,
          "variables": ["id": userBookId, "status": statusId]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await URLSession.shared.data(for: request)
          if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
              if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty { return false }
              if let dataDict = json["data"] as? [String: Any],
                 let update = dataDict["update_user_book"] as? [String: Any] {
                  if let err = update["error"] as? String, !err.isEmpty { return false }
                  return update["user_book"] != nil
              }
          }
      } catch {
          print("❌ updateUserBook Error: \(error)")
      }
      return false
  }
  
  static func deleteUserBook(userBookId: Int) async -> Bool {
      guard !HardcoverConfig.apiKey.isEmpty else { return false }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      let body: [String: Any] = [
          "query": """
          mutation($id: Int!) { delete_user_book(id: $id) { id } }
          """,
          "variables": ["id": userBookId]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await URLSession.shared.data(for: request)
          if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
              if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty { return false }
              if let dataDict = json["data"] as? [String: Any],
                 let del = dataDict["delete_user_book"] as? [String: Any] {
                  return del["id"] != nil
              }
          }
      } catch {
          print("❌ deleteUserBook Error: \(error)")
      }
      return false
  }
  
  private static func fetchUserBook(by userBookId: Int) async -> UserBook? {
      guard !HardcoverConfig.apiKey.isEmpty else { return nil }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      let body: [String: Any] = [
          "query": """
          query GetUserBook($id: Int!) {
            user_books(where: { id: { _eq: $id }}) {
              id
              book_id
              status_id
              edition_id
              privacy_setting_id
              rating
            }
          }
          """,
          "variables": ["id": userBookId]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await URLSession.shared.data(for: request)
          let resp = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data)
          if let errs = resp.errors, !errs.isEmpty { return nil }
          return resp.data?.user_books?.first
      } catch {
          print("❌ fetchUserBook error: \(error)")
          return nil
      }
  }
  
  private static func fetchAccountPrivacySettingId() async -> Int? {
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      let body: [String: Any] = [
          "query": """
          { me { account_privacy_setting_id } }
          """
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await URLSession.shared.data(for: request)
          if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
             let dataDict = root["data"] as? [String: Any],
             let meArr = dataDict["me"] as? [[String: Any]],
             let first = meArr.first,
             let val = first["account_privacy_setting_id"] as? Int {
              return val
          }
      } catch {
          print("❌ fetchAccountPrivacySettingId error: \(error)")
      }
      return nil
  }
  
  // MARK: - Reading Stats
  struct ReadingStats {
      let fromDate: String
      let toDate: String
      let booksFinished: Int
      let estimatedPages: Int
      let averageRating: Double?
  }
  
  static func fetchReadingStats(year: Int?) async -> ReadingStats? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { return nil }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($userId: Int!) {
          user_books(where: { user_id: { _eq: $userId }, status_id: { _eq: 3 } }) {
            id
            rating
            edition { pages }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            guard let dataDict = root["data"] as? [String: Any],
                  let userBooks = dataDict["user_books"] as? [[String: Any]] else { return nil }
            
            let booksFinished = userBooks.count
            let pagesSum = userBooks.reduce(0) { sum, ub in
                let pages = (ub["edition"] as? [String: Any])?["pages"] as? Int ?? 0
                return sum + max(0, pages)
            }
            let ratings = userBooks.compactMap { $0["rating"] as? Double }
            let avg = ratings.isEmpty ? nil : (ratings.reduce(0, +) / Double(ratings.count))
            
            let from = "1900-01-01"
            let to = "2999-01-01"
            return ReadingStats(fromDate: from, toDate: to, booksFinished: booksFinished, estimatedPages: pagesSum, averageRating: avg)
        } catch {
            return nil
        }
    }
    
    // MARK: - Reading Goals
    private static let enableGoalSelfHeal = true
    private static let countRereadsAsMultiple = true
    
    private static func parseAPITimestamp(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
    
    private static func countFinishedBooks(userId: Int, startDate: String, endDate: String) async -> Int {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($userId: Int!, $start: date!, $end: date!) {
          user_book_reads(
            where: {
              finished_at: { _is_null: false, _gte: $start, _lte: $end },
              user_book: { user_id: { _eq: $userId } }
            }
          ) {
            id
            user_book_id
            finished_at
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId, "start": startDate, "end": endDate]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = root["data"] as? [String: Any],
                  let reads = dataDict["user_book_reads"] as? [[String: Any]] else {
                return 0
            }
            if countRereadsAsMultiple {
                return reads.count
            } else {
                let uniqueBookIds = Set(reads.compactMap { $0["user_book_id"] as? Int })
                return uniqueBookIds.count
            }
        } catch {
            return 0
        }
    }
    
    static func fetchReadingGoals() async -> [ReadingGoal] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        
        // First try: Direct goals query via me
        if let goals = await tryFetchGoalsDirectly() {
            return goals
        }
        
        // Fallback: Activities approach
        return await fetchGoalsViaActivities()
    }
    
    private static func tryFetchGoalsDirectly() async -> [ReadingGoal]? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let query = """
        query {
            me {
                goals {
                    id
                    goal
                    metric
                    start_date
                    end_date
                    progress
                    description
                    privacy_setting_id
                }
            }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 Direct goals query response: \(jsonString)")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let meArray = dataDict["me"] as? [[String: Any]],
                  let me = meArray.first,
                  let goalsArray = me["goals"] as? [[String: Any]] else {
                print("⚠️ Direct goals query not supported, falling back to activities")
                return nil
            }
            
            print("✅ Found goals directly via me.goals: \(goalsArray.count)")
            var goals: [ReadingGoal] = []
            for goalDict in goalsArray {
                do {
                    let goalData = try JSONSerialization.data(withJSONObject: goalDict)
                    let goal = try JSONDecoder().decode(ReadingGoal.self, from: goalData)
                    print("🎯 Direct goal ID \(goal.id): \(goal.goal) \(goal.metric)")
                    goals.append(goal)
                } catch {
                    print("❌ Failed to decode goal: \(error)")
                }
            }
            return goals
        } catch {
            print("⚠️ Direct goals query failed: \(error)")
            return nil
        }
    }
    
    private static func fetchGoalsViaActivities() async -> [ReadingGoal] {
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { return [] }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        // Disable caching to ensure we get fresh reading goals data
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let query = """
        query GetReadingGoals($userId: Int!) {
            activities(where: {user_id: {_eq: $userId}, event: {_eq: "GoalActivity"}}, order_by: {id: desc}, limit: 100) {
                id
                event
                data
                created_at
            }
        }
        """
        
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // DEBUG: Print raw JSON response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 Raw goals API response: \(jsonString)")
            }
            
            let gqlResponse = try JSONDecoder().decode(GraphQLActivitiesResponse.self, from: data)
            if let errors = gqlResponse.errors, !errors.isEmpty { 
                print("❌ GraphQL activities API errors: \(errors)")
                return [] 
            }
            guard let activities = gqlResponse.data?.activities else { 
                print("❌ No activities data found")
                return [] 
            }
            
            print("🎯 fetchReadingGoals: Found \(activities.count) goal activities (sorted by ID desc)")
            
            // Group by goal ID and take the HIGHEST activity ID (most recent update)
            var latestByGoal: [Int: (goal: ReadingGoal, activityId: Int)] = [:]
            for activity in activities {
                guard activity.event == "GoalActivity",
                      let goal = activity.data?.goal,
                      let activityId = activity.id else { continue }
                print("🎯 Activity ID \(activityId): Goal ID \(goal.id) = \(goal.goal) \(goal.metric) (created: \(activity.created_at ?? "nil"))")
                if let existing = latestByGoal[goal.id] {
                    if activityId > existing.activityId {
                        print("  ↳ Updating to newer activity (higher ID)")
                        latestByGoal[goal.id] = (goal, activityId)
                    }
                } else {
                    latestByGoal[goal.id] = (goal, activityId)
                }
            }
            var goals = latestByGoal.values.map { $0.goal }
            print("🎯 Final goals after deduplication: \(goals.count)")
            if enableGoalSelfHeal {
                var healed: [ReadingGoal] = []
                for g in goals {
                    if g.metric.lowercased() == "book" {
                        let counted = await countFinishedBooks(userId: userId, startDate: g.startDate, endDate: g.endDate)
                        if counted > g.progress {
                            let newPercent = min(1.0, Double(counted) / Double(max(g.goal, 1)))
                            if let healedGoal = healGoalProgress(original: g, newProgress: counted, newPercent: newPercent) {
                                healed.append(healedGoal); continue
                            }
                        }
                    }
                    healed.append(g)
                }
                goals = healed
            }
            return goals
        } catch {
            return []
        }
    }
    
    private static func healGoalProgress(original: ReadingGoal, newProgress: Int, newPercent: Double) -> ReadingGoal? {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(original)
            var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            obj["progress"] = newProgress
            obj["percentComplete"] = newPercent
            let newData = try JSONSerialization.data(withJSONObject: obj)
            let healed = try JSONDecoder().decode(ReadingGoal.self, from: newData)
            return healed
        } catch {
            return nil
        }
    }
    
    // MARK: - Reading History
    static func fetchReadingHistory(limit: Int, offset: Int) async -> [FinishedBookEntry] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($userId: Int!, $limit: Int!, $offset: Int!) {
          user_book_reads(
            where: { finished_at: { _is_null: false }, user_book: { user_id: { _eq: $userId } } },
            order_by: [{ finished_at: desc }, { id: desc }],
            limit: $limit,
            offset: $offset
          ) {
            id
            finished_at
            edition_id
            user_book {
              id
              book_id
              rating
              book {
                id
                title
                contributions { author { name } }
                image { url }
              }
              edition {
                id
                title
                image { url }
              }
            }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId, "limit": limit, "offset": offset]
        ]
        
        func parseDate(_ s: String) -> Date? {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: s) { return d }
            return parseAPITimestamp(s)
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { return [] }
            guard let dataDict = root["data"] as? [String: Any],
                  let reads = dataDict["user_book_reads"] as? [[String: Any]] else {
                return []
            }
            
            var results: [FinishedBookEntry] = []
            results.reserveCapacity(reads.count)
            
            for read in reads {
                guard let readId = read["id"] as? Int,
                      let finishedAtStr = read["finished_at"] as? String,
                      let finishedDate = parseDate(finishedAtStr),
                      let userBook = read["user_book"] as? [String: Any],
                      let bookId = userBook["book_id"] as? Int
                else { continue }
                
                let userBookId = userBook["id"] as? Int
                let rating = userBook["rating"] as? Double
                
                let editionDict = userBook["edition"] as? [String: Any]
                let editionTitle = editionDict?["title"] as? String
                let bookDict = userBook["book"] as? [String: Any]
                let bookTitle = (bookDict?["title"] as? String) ?? "Unknown Title"
                let displayTitle = (editionTitle?.isEmpty == false) ? editionTitle! : bookTitle
                
                var author = "Unknown Author"
                if let contributions = bookDict?["contributions"] as? [[String: Any]],
                   let first = contributions.first,
                   let a = (first["author"] as? [String: Any])?["name"] as? String,
                   !a.isEmpty {
                    author = a
                }
                
                var coverUrl: String? = nil
                if let img = (editionDict?["image"] as? [String: Any])?["url"] as? String, !img.isEmpty {
                    coverUrl = img
                } else if let img = (bookDict?["image"] as? [String: Any])?["url"] as? String, !img.isEmpty {
                    coverUrl = img
                }
                
                var coverData: Data? = nil
                if let urlStr = coverUrl {
                    coverData = await fetchAndResizeImage(from: urlStr)
                }
                
                let entry = FinishedBookEntry(
                    id: readId,
                    bookId: bookId,
                    userBookId: userBookId,
                    title: displayTitle,
                    author: author,
                    rating: rating,
                    finishedAt: finishedDate,
                    coverImageData: coverData,
                    coverImageUrl: nil
                )
                results.append(entry)
            }
            
            return results
        } catch {
            return []
        }
    }
}

// MARK: - Finish book helpers
extension HardcoverService {
    static func finishBook(userBookId: Int, editionId: Int?, totalPages: Int?, currentPage: Int?, rating: Double?) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        var statusOK = true
        if let value = rating {
            let clamped = max(0.5, min(5.0, (round(value * 2) / 2)))
            statusOK = await updateUserBook(userBookId: userBookId, statusId: 3, rating: clamped)
        } else {
            statusOK = await updateUserBookStatus(userBookId: userBookId, statusId: 3)
        }
        if !statusOK { return false }
        
        let today = utcDateString()
        var finishedOK = false
        if let readId = await fetchLatestReadId(userBookId: userBookId) {
            finishedOK = await updateReadFinishedAt(readId: readId, finishedAt: today)
        }
        if !finishedOK {
            let pages: Int? = totalPages ?? currentPage
            finishedOK = await insertFinishedRead(userBookId: userBookId, editionId: editionId, pages: pages, finishedAt: today)
        }
        return finishedOK
    }
    
    // Update user book status with last_read_date (for changing status of already read books)
    static func updateUserBookWithDate(userBookId: Int, editionId: Int?, statusId: Int, rating: Double?, lastReadDate: String?, dateAdded: String?, userDate: String?) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        var object: [String: Any] = ["status_id": statusId]
        if let eid = editionId { object["edition_id"] = eid }
        if let r = rating { object["rating"] = r }
        if let date = lastReadDate { object["last_read_date"] = date }
        if let added = dateAdded { object["date_added"] = added }
        if let udate = userDate { object["user_date"] = udate }
        object["review_has_spoilers"] = false
        object["privacy_setting_id"] = 1
        
        let mutation = """
        mutation UpdateUserBook($id: Int!, $object: UserBookUpdateInput!) {
          update_user_book(id: $id, object: $object) {
            error
            user_book { id status_id rating }
          }
        }
        """
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["id": userBookId, "object": object]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { return false }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["update_user_book"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty { return false }
                    return update["user_book"] != nil
                }
            }
        } catch {
            return false
        }
        return false
    }
    
    static func updateUserBook(userBookId: Int, statusId: Int, rating: Double?) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        var object: [String: Any] = ["status_id": statusId]
        if let r = rating { object["rating"] = r }
        
        let mutation = """
        mutation UpdateUserBook($id: Int!, $object: UserBookUpdateInput!) {
          update_user_book(id: $id, object: $object) {
            error
            user_book { id status_id rating }
          }
        }
        """
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["id": userBookId, "object": object]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { return false }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["update_user_book"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty { return false }
                    return update["user_book"] != nil
                }
            }
        } catch {
            return false
        }
        return false
    }
    
    static func updateUserBookRating(userBookId: Int, rating: Double?) async -> Bool {
        print("🎯 updateUserBookRating called with userBookId: \(userBookId), rating: \(rating ?? 0.0)")
        guard !HardcoverConfig.apiKey.isEmpty else { 
            print("❌ API key is empty")
            return false 
        }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { 
            print("❌ Invalid URL")
            return false 
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let mutation = """
        mutation ($id: Int!, $rating: float8) {
          update_user_book(id: $id, object: { rating: $rating }) {
            error
            user_book { id rating }
          }
        }
        """
        let vars: [String: Any] = ["id": userBookId, "rating": rating as Any]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = bodyData
            print("🌐 Sending updateUserBookRating request...")
            let (data, _) = try await URLSession.shared.data(for: request)
            print("📡 Received response data: \(data.count) bytes")
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("📄 Response JSON: \(root)")
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { 
                    print("❌ GraphQL errors: \(errs)")
                    return false 
                }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["update_user_book"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty { 
                        print("❌ Update error: \(err)")
                        return false 
                    }
                    let success = update["user_book"] != nil
                    print("✅ updateUserBookRating success: \(success)")
                    return success
                }
            }
        } catch {
            print("❌ updateUserBookRating exception: \(error)")
            return false
        }
        print("❌ updateUserBookRating failed - no valid response")
        return false
    }
    
    private static func updateReadFinishedAt(readId: Int, finishedAt: String) async -> Bool {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "query": """
            mutation ($id: Int!, $finished: date) {
              update_user_book_read(id: $id, object: { finished_at: $finished }) {
                error
                user_book_read { id finished_at }
              }
            }
            """,
            "variables": ["id": readId, "finished": finishedAt]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { return false }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["update_user_book_read"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty { return false }
                    return update["user_book_read"] != nil
                }
            }
        } catch {
            return false
        }
        return false
    }
    
    private static func insertFinishedRead(userBookId: Int, editionId: Int?, pages: Int?, finishedAt: String) async -> Bool {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        var vars: [String: Any] = ["id": userBookId, "finishedAt": finishedAt]
        if let p = pages { vars["pages"] = max(0, p) }
        if let eid = editionId { vars["editionId"] = eid }
        
        let mutation = """
        mutation InsertFinishedRead($id: Int!, $pages: Int, $editionId: Int, $finishedAt: date) {
          insert_user_book_read(user_book_id: $id, user_book_read: {
            progress_pages: $pages,
            edition_id: $editionId,
            finished_at: $finishedAt
          }) {
            error
            user_book_read { id progress_pages edition_id started_at finished_at }
          }
        }
        """
        let body: [String: Any] = ["query": mutation, "variables": vars]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { return false }
                if let dataDict = root["data"] as? [String: Any],
                   let insert = dataDict["insert_user_book_read"] as? [String: Any] {
                    if let err = insert["error"] as? String, !err.isEmpty { return false }
                    return insert["user_book_read"] != nil
                }
            }
        } catch {
            return false
        }
        return false
    }
    
    private static func utcDateString() -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}

// MARK: - Upcoming Releases (Want to read -> future editions)
extension HardcoverService {
    struct UpcomingRelease: Identifiable {
        let id: Int            // edition id
        let bookId: Int?
        let title: String
        let author: String
        let releaseDate: Date
        let coverImageData: Data?
    }
    
    static func fetchUpcomingReleasesFromWantToRead(limit: Int = 30) async -> [UpcomingRelease] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($userId: Int!, $statusId: Int!) {
          user_books(
            where: { user_id: { _eq: $userId }, status_id: { _eq: $statusId } },
            order_by: { id: desc },
            limit: 500
          ) {
            id
            book_id
            edition_id
            book {
              id
              title
              contributions { author { name } }
              image { url }
              editions(where: { release_date: { _is_null: false } }) {
                id
                title
                release_date
                image { url }
              }
            }
            edition {
              id
              title
              release_date
              image { url }
            }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId, "statusId": 1]
        ]
        
        func parseDate(_ s: String) -> Date? {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: s)
        }
        
        struct TempRelease {
            let id: Int
            let bookId: Int?
            let title: String
            let author: String
            let releaseDate: Date
            let coverUrl: String?
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            let resp = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data)
            if let errs = resp.errors, !errs.isEmpty {
                return []
            }
            guard let rows = resp.data?.user_books else { return [] }
            
            let today = Calendar.current.startOfDay(for: Date())
            var temps: [TempRelease] = []
            temps.reserveCapacity(rows.count)
            
            for ub in rows {
                // 1) Respektera vald edition först om den har framtida release
                if let chosen = ub.edition,
                   let s = chosen.releaseDate,
                   let d = parseDate(s),
                   d >= today {
                    let rawTitle = (chosen.title?.isEmpty == false) ? chosen.title! : (ub.book?.title ?? "Unknown Title")
                    let title = rawTitle.decodedHTMLEntities
                    let author = ub.book?.contributions?.first?.author?.name ?? "Unknown Author"
                    var coverUrl: String? = nil
                    if let u = chosen.image?.url, !u.isEmpty { coverUrl = u }
                    else if let u = ub.book?.image?.url, !u.isEmpty { coverUrl = u }
                    temps.append(TempRelease(id: chosen.id, bookId: ub.book?.id, title: title, author: author, releaseDate: d, coverUrl: coverUrl))
                    continue
                }
                
                // 2) Annars, välj tidigaste framtida bland övriga editioner under boken
                var candidates: [Edition] = []
                if let more = ub.book?.editions { candidates.append(contentsOf: more) }
                let futureCandidates: [(Edition, Date)] = candidates.compactMap { ed in
                    guard let s = ed.releaseDate, let d = parseDate(s) else { return nil }
                    return d >= today ? (ed, d) : nil
                }
                guard let best = futureCandidates.sorted(by: { $0.1 < $1.1 }).first else { continue }
                let chosenEdition = best.0
                let rd = best.1
                
                let rawTitle = (chosenEdition.title?.isEmpty == false) ? chosenEdition.title! : (ub.book?.title ?? "Unknown Title")
                let title = rawTitle.decodedHTMLEntities
                let author = ub.book?.contributions?.first?.author?.name ?? "Unknown Author"
                var coverUrl: String? = nil
                if let u = chosenEdition.image?.url, !u.isEmpty { coverUrl = u }
                else if let u = ub.book?.image?.url, !u.isEmpty { coverUrl = u }
                
                temps.append(TempRelease(id: chosenEdition.id, bookId: ub.book?.id, title: title, author: author, releaseDate: rd, coverUrl: coverUrl))
            }
            
            // Sortera, beskära till limit, och hämta bilder ENDAST för dessa
            let sorted = temps.sorted { $0.releaseDate < $1.releaseDate }
            let limited = Array(sorted.prefix(limit))
            
            var items: [UpcomingRelease] = []
            items.reserveCapacity(limited.count)
            for t in limited {
                let data: Data? = (t.coverUrl != nil) ? await fetchAndResizeImage(from: t.coverUrl!) : nil
                items.append(UpcomingRelease(id: t.id, bookId: t.bookId, title: t.title, author: t.author, releaseDate: t.releaseDate, coverImageData: data))
            }
            return items
        } catch {
            return []
        }
    }
}

// MARK: - Recent Releases (Nyligen släppta böcker från Want to Read)
extension HardcoverService {
    static func fetchRecentReleasesFromWantToRead(limit: Int = 10) async -> [HardcoverService.UpcomingRelease] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($userId: Int!, $statusId: Int!) {
          user_books(
            where: { user_id: { _eq: $userId }, status_id: { _eq: $statusId } },
            order_by: { id: desc },
            limit: 500
          ) {
            id
            book_id
            edition_id
            book {
              id
              title
              contributions { author { name } }
              image { url }
              editions(where: { release_date: { _is_null: false } }) {
                id
                title
                release_date
                image { url }
              }
            }
            edition {
              id
              title
              release_date
              image { url }
            }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId, "statusId": 1]
        ]
        
        func parseDate(_ s: String) -> Date? {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: s)
        }
        
        struct TempRelease {
            let id: Int
            let bookId: Int?
            let title: String
            let author: String
            let releaseDate: Date
            let coverUrl: String?
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            let resp = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data)
            if let errs = resp.errors, !errs.isEmpty {
                return []
            }
            guard let rows = resp.data?.user_books else { return [] }
            
            let today = Calendar.current.startOfDay(for: Date())
            var temps: [TempRelease] = []
            temps.reserveCapacity(rows.count)
            
            for ub in rows {
                // Kolla först den valda editionen
                if let chosen = ub.edition,
                   let s = chosen.releaseDate,
                   let d = parseDate(s),
                   d < today {
                    let rawTitle = (chosen.title?.isEmpty == false) ? chosen.title! : (ub.book?.title ?? "Unknown Title")
                    let title = rawTitle.decodedHTMLEntities
                    let author = ub.book?.contributions?.first?.author?.name ?? "Unknown Author"
                    var coverUrl: String? = nil
                    if let u = chosen.image?.url, !u.isEmpty { coverUrl = u }
                    else if let u = ub.book?.image?.url, !u.isEmpty { coverUrl = u }
                    temps.append(TempRelease(id: chosen.id, bookId: ub.book?.id, title: title, author: author, releaseDate: d, coverUrl: coverUrl))
                    continue
                }
                
            }
            
            // Sortera efter releasedatum (senaste först) och begränsa till limit
            let sorted = temps.sorted { $0.releaseDate > $1.releaseDate }
            let limited = Array(sorted.prefix(limit))
            
            var items: [UpcomingRelease] = []
            items.reserveCapacity(limited.count)
            for t in limited {
                let data: Data? = (t.coverUrl != nil) ? await fetchAndResizeImage(from: t.coverUrl!) : nil
                items.append(UpcomingRelease(id: t.id, bookId: t.bookId, title: t.title, author: t.author, releaseDate: t.releaseDate, coverImageData: data))
            }
            return items
        } catch {
            return []
        }
    }
}

// MARK: - Trending & Search Details helpers required by SearchBooksView
extension HardcoverService {
    // Minimal model to support SearchBooksView's UI
    struct TrendingBook: Identifiable {
        let id: Int          // book id
        let title: String
        let author: String
        let coverImageUrl: String?
        let usersCount: Int
    }
    
    /// Fetch trending books for the month.
    /// Now uses HTML scraping from hardcover.app/trending instead of GraphQL.
    static func fetchTrendingBooksMonthly(limit: Int, imageMaxPixel: Int = 280, compression: CGFloat = 0.75) async -> [TrendingBook] {
        guard !HardcoverConfig.apiKey.isEmpty else { 
            print("❌ No API key available")
            return [] 
        }
        
        guard let url = URL(string: "https://hardcover.app/trending/month") else { 
            print("❌ Invalid URL")
            return [] 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📊 Status code: \(httpResponse.statusCode)")
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ Could not decode HTML")
                return []
            }
            
            // Debug: Print first 500 chars of HTML
            let preview = String(html.prefix(500))
            print("📄 HTML preview: \(preview)")
            
            // Extract trending books from HTML using Inertia.js data-page attribute
            if let books = extractTrendingBooksFromHTML(html, limit: limit) {
                print("✅ Parsed \(books.count) trending books")
                return books
            }
            
            print("❌ Could not extract books from HTML")
            return []
        } catch {
            print("❌ Failed to fetch trending books: \(error)")
            return []
        }
    }
    
    /// Extract trending books from Inertia.js data-page attribute in HTML
    private static func extractTrendingBooksFromHTML(_ html: String, limit: Int) -> [TrendingBook]? {
        // Find data-page attribute
        guard let dataPageRange = html.range(of: "data-page=\"") else {
            print("❌ Could not find data-page attribute")
            return nil
        }
        
        let startIndex = dataPageRange.upperBound
        guard let endIndex = html[startIndex...].range(of: "\">")?.lowerBound else {
            print("❌ Could not find end of data-page attribute")
            return nil
        }
        
        let jsonString = String(html[startIndex..<endIndex])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Could not convert JSON string to data")
            return nil
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let props = json["props"] as? [String: Any],
                  let booksArray = props["books"] as? [[String: Any]] else {
                print("❌ Could not parse books from JSON")
                return nil
            }
            
            print("📖 First book structure:")
            if let firstBook = booksArray.first {
                print("  Keys: \(firstBook.keys.sorted())")
                if let image = firstBook["image"] {
                    print("  image: \(image)")
                }
            }
            
            var items: [TrendingBook] = []
            items.reserveCapacity(min(booksArray.count, limit))
            
            for bookDict in booksArray.prefix(limit) {
                guard let id = bookDict["id"] as? Int else { continue }
                
                let rawTitle = (bookDict["title"] as? String) ?? "Unknown Title"
                let title = rawTitle.decodedHTMLEntities
                
                var author = "Unknown Author"
                if let contributions = bookDict["contributions"] as? [[String: Any]],
                   let firstContribution = contributions.first,
                   let authorDict = firstContribution["author"] as? [String: Any],
                   let authorName = authorDict["name"] as? String {
                    author = authorName
                }
                
                let usersCount = (bookDict["usersCount"] as? Int) ?? 0
                
                var imageUrl: String?
                if let image = bookDict["image"] as? [String: Any],
                   let url = image["url"] as? String {
                    imageUrl = url
                }
                
                items.append(TrendingBook(id: id, title: title, author: author, coverImageUrl: imageUrl, usersCount: usersCount))
            }
            
            return items
        } catch {
            print("❌ JSON parsing error: \(error)")
            return nil
        }
    }
    
    /// Fetch a richer book detail by id to power the search result detail sheet.
    static func fetchBookDetailsById(bookId: Int, userBookId: Int?, imageMaxPixel: Int = 360, compression: CGFloat = 0.8) async -> BookProgress? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            title
            description
            contributions { author { name } }
            image { url }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["id": bookId]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataDict = root["data"] as? [String: Any],
                let books = dataDict["books"] as? [[String: Any]],
                let first = books.first
            else { return nil }
            
            let rawTitle = (first["title"] as? String) ?? "Unknown Title"
            let title = rawTitle.decodedHTMLEntities
            let author: String = {
                if let contribs = first["contributions"] as? [[String: Any]],
                   let firstC = contribs.first,
                   let a = (firstC["author"] as? [String: Any])?["name"] as? String,
                   !a.isEmpty {
                    return a
                }
                return "Unknown Author"
            }()
            let desc = first["description"] as? String
            var coverData: Data? = nil
            if let img = (first["image"] as? [String: Any])?["url"] as? String, !img.isEmpty {
                coverData = await fetchAndResizeImage(from: img)
            }
            
            return BookProgress(
                id: "book-\(bookId)",
                title: title,
                author: author,
                coverImageData: coverData,
                progress: 0.0,
                totalPages: 0,
                currentPage: 0,
                bookId: bookId,
                userBookId: userBookId,
                editionId: nil,
                originalTitle: title,
                editionAverageRating: nil,
                userRating: nil,
                bookDescription: desc
            )
        } catch {
            return nil
        }
    }
    
    /// Finish a book by its book id (creates/updates a user_book row with status_id = 3).
    static func finishBookByBookId(bookId: Int, editionId: Int?, pages: Int?, rating: Double?) async -> Bool {
        print("🎯 finishBookByBookId called with bookId: \(bookId), editionId: \(editionId ?? -1), rating: \(rating ?? 0.0)")
        guard !HardcoverConfig.apiKey.isEmpty else { 
            print("❌ API key is empty")
            return false 
        }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { 
            print("❌ Invalid URL")
            return false 
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let privacySetting = await fetchAccountPrivacySettingId() ?? 1
        print("🔐 Privacy setting: \(privacySetting)")
        
        var object: [String: Any] = [
            "book_id": bookId,
            "status_id": 3,
            "privacy_setting_id": privacySetting
        ]
        if let eid = editionId { object["edition_id"] = eid }
        if let r = rating { object["rating"] = r }
        print("📦 Object to send: \(object)")
        
        let mutation = """
        mutation InsertUserBook($object: UserBookCreateInput!) {
          insert_user_book(object: $object) {
            error
            user_book { id book_id edition_id status_id privacy_setting_id }
          }
        }
        """
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["object": object]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("🌐 Sending finishBookByBookId request...")
            let (data, _) = try await URLSession.shared.data(for: request)
            print("📡 Received response data: \(data.count) bytes")
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("📄 Response JSON: \(root)")
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { 
                    print("❌ GraphQL errors: \(errs)")
                    return false 
                }
                if let dataDict = root["data"] as? [String: Any],
                   let insert = dataDict["insert_user_book"] as? [String: Any] {
                    if let err = insert["error"] as? String, !err.isEmpty { 
                        print("❌ Insert error: \(err)")
                        return false 
                    }
                    let success = insert["user_book"] != nil
                    print("✅ finishBookByBookId success: \(success)")
                    if let userBook = insert["user_book"] as? [String: Any] {
                        print("👤 Created user_book: \(userBook)")
                    }
                    return success
                }
            }
        } catch {
            print("❌ finishBookByBookId exception: \(error)")
            return false
        }
        print("❌ finishBookByBookId failed - no valid response")
        return false
    }
    
    /// Add a book to Want to Read (status_id = 1).
    static func addBookToWantToRead(bookId: Int, editionId: Int?) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        let privacySetting = await fetchAccountPrivacySettingId() ?? 1

        var object: [String: Any] = [
            "book_id":  bookId,
            "status_id": 1,
            "privacy_setting_id": privacySetting
        ]
        if let eid = editionId { object["edition_id"] = eid }

        let body: [String: Any] = [
            "query": """
            mutation InsertUserBook($object: UserBookCreateInput!) {
              insert_user_book(object: $object) {
                error
                user_book { id book_id edition_id status_id privacy_setting_id }
              }
            }
            """,
            "variables": ["object": object]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse { print("📥 Insert user_book HTTP Status: \(http.statusCode)") }
            if let raw = String(data: data, encoding: .utf8) { print("📥 Insert user_book Raw: \(raw)") }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty {
                    print("❌ Insert user_book GraphQL errors: \(errs)")
                    return false
                }
                if let dataDict = json["data"] as? [String: Any],
                   let insert = dataDict["insert_user_book"] as? [String: Any] {
                    if let err = insert["error"] as? String, !err.isEmpty {
                        print("❌ Insert user_book error: \(err)")
                        return false
                    }
                    return insert["user_book"] != nil
                }
            }
            return false
        } catch {
            print("❌ Insert user_book Error: \(error)")
            return false
        }
    }

    /// Create a user book with rating using the same mutation as Hardcover.app
    static func createUserBookWithRating(bookId: Int, editionId: Int?, rating: Double) async -> Int? {
        print("🎯 createUserBookWithRating called with bookId: \(bookId), editionId: \(editionId ?? -1), rating: \(rating)")
        guard !HardcoverConfig.apiKey.isEmpty else { 
            print("❌ API key is empty")
            return nil 
        }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { 
            print("❌ Invalid URL")
            return nil 
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let privacySetting = await fetchAccountPrivacySettingId() ?? 1
        print("🔐 Privacy setting: \(privacySetting)")
        
        var variables: [String: Any] = [
            "bookId": bookId,
            "statusId": 3, // Finished
            "rating": rating,
            "privacySettingId": privacySetting
        ]
        if let eid = editionId { 
            variables["editionId"] = eid 
        }
        print("📦 Variables to send: \(variables)")
        
        // This mutation matches what Hardcover.app uses
        let mutation = """
        mutation CreateUserBook($bookId: Int!, $editionId: Int, $statusId: Int!, $rating: Float!, $privacySettingId: Int!) {
          insertResponse: insert_user_book(object: {
            book_id: $bookId,
            edition_id: $editionId,
            status_id: $statusId,
            rating: $rating,
            privacy_setting_id: $privacySettingId
          }) {
            error
            userBook: user_book {
              id
              bookId: book_id
              editionId: edition_id
              userId: user_id
              statusId: status_id
              rating
              privacySettingId: privacy_setting_id
              hasReview: has_review
              edition {
                id
                title
                asin
                isbn10
                isbn13
                releaseDate: release_date
                releaseYear: release_year
                pages
                audioSeconds: audio_seconds
                readingFormatId: reading_format_id
                usersCount: users_count
                image {
                  id
                  url
                  color
                  width
                  height
                  color_name
                }
                editionFormat: edition_format
                editionInformation: edition_information
                language {
                  id
                  language
                  code
                  __typename
                }
                readingFormat: reading_format {
                  format
                  __typename
                }
                country {
                  name
                  __typename
                }
                publisher {
                  id
                  name
                  slug
                  state
                  editionsCount: editions_count
                  userId: user_id
                  __typename
                }
                __typename
              }
              datesRead: dates_read {
                id
                userBookId: user_book_id
                startedAt: started_at
                finishedAt: finished_at
                editionId: edition_id
                progress
                progressPages: progress_pages
                progressSeconds: progress_seconds
                edition {
                  id
                  title
                  asin
                  isbn10
                  isbn13
                  releaseDate: release_date
                  releaseYear: release_year
                  pages
                  audioSeconds: audio_seconds
                  readingFormatId: reading_format_id
                  usersCount: users_count
                  image {
                    id
                    url
                    color
                    width
                    height
                    color_name
                  }
                  editionFormat: edition_format
                  editionInformation: edition_information
                  language {
                    id
                    language
                    code
                    __typename
                  }
                  readingFormat: reading_format {
                    format
                    __typename
                  }
                  country {
                    name
                    __typename
                  }
                  publisher {
                    id
                    name
                    slug
                    state
                    editionsCount: editions_count
                    userId: user_id
                    __typename
                  }
                  __typename
                }
                __typename
              }
              __typename
            }
            __typename
          }
        }
        """
        
        let body: [String: Any] = [
            "query": mutation,
            "variables": variables
        ]
        
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = bodyData
            print("🚀 Sending request...")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            print("📨 Got response data")
            
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("📋 Response: \(root)")
                
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { 
                    print("❌ GraphQL errors: \(errs)")
                    return nil 
                }
                
                if let dataDict = root["data"] as? [String: Any],
                   let insertResponse = dataDict["insertResponse"] as? [String: Any] {
                    
                    if let err = insertResponse["error"] as? String, !err.isEmpty { 
                        print("❌ Insert error: \(err)")
                        return nil 
                    }
                    
                    if let userBook = insertResponse["userBook"] as? [String: Any],
                       let userBookId = userBook["id"] as? Int {
                        print("✅ Successfully created userBook with id: \(userBookId)")
                        return userBookId
                    }
                }
            }
        } catch {
            print("❌ Request failed: \(error)")
            return nil
        }
        
        print("❌ Failed to create user book")
        return nil
    }
    
    // MARK: - Reading Dates Management
    
    struct ReadingDate: Identifiable, Codable {
        let id: Int
        let startedAt: String?
        let finishedAt: String?
        let editionId: Int?
        let progressPages: Int?
        
        var startDate: Date? {
            guard let str = startedAt else { return nil }
            return parseDate(str)
        }
        
        var endDate: Date? {
            guard let str = finishedAt else { return nil }
            return parseDate(str)
        }
        
        private func parseDate(_ str: String) -> Date? {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "UTC")
            return df.date(from: str)
        }
    }
    
    static func fetchReadingDates(userBookId: Int) async -> [ReadingDate] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($id: Int!) {
          user_book_reads(where: { user_book_id: { _eq: $id } }, order_by: { started_at: desc }) {
            id
            started_at
            finished_at
            edition_id
            progress_pages
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["id": userBookId]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let reads = dataDict["user_book_reads"] as? [[String: Any]] {
                return reads.compactMap { read in
                    guard let id = read["id"] as? Int else { return nil }
                    return ReadingDate(
                        id: id,
                        startedAt: read["started_at"] as? String,
                        finishedAt: read["finished_at"] as? String,
                        editionId: read["edition_id"] as? Int,
                        progressPages: read["progress_pages"] as? Int
                    )
                }
            }
        } catch {
            return []
        }
        return []
    }
    
    static func updateReadingDate(readId: Int, startedAt: String?, finishedAt: String?, editionId: Int?) async -> Bool {
        print("📅 updateReadingDate called - readId: \(readId), startedAt: \(startedAt ?? "nil"), finishedAt: \(finishedAt ?? "nil")")
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ API key is empty")
            return false
        }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid URL")
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        var object: [String: Any] = [:]
        
        // Only include fields that are explicitly provided
        if let started = startedAt { 
            object["started_at"] = started 
        }
        if let finished = finishedAt { 
            object["finished_at"] = finished 
            // When setting finished date, clear progress
            object["progress_pages"] = NSNull()
            object["progress_seconds"] = NSNull()
        } else if startedAt != nil {
            // When only setting start date (no finish), set progress to 0
            object["progress_pages"] = 0
            object["progress_seconds"] = 0
        }
        
        if let eid = editionId, eid > 0 { 
            object["edition_id"] = eid 
        }
        
        let mutation = """
        mutation UpdateUserBookReadMutation($id: Int!, $object: DatesReadInput!) {
          updateResult: update_user_book_read(id: $id, object: $object) {
            error
            userBookRead: user_book_read {
              id
              started_at
              finished_at
            }
          }
        }
        """
        let body: [String: Any] = [
            "operationName": "UpdateUserBookReadMutation",
            "query": mutation,
            "variables": ["id": readId, "object": object]
        ]
        
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = bodyData
            print("🚀 Sending update request...")
            print("📦 Body: \(String(data: bodyData, encoding: .utf8) ?? "invalid")")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let responseString = String(data: data, encoding: .utf8) ?? "invalid"
            print("📨 Response: \(responseString)")
            
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                    print("❌ GraphQL errors: \(errs)")
                    return false
                }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["updateResult"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty {
                        print("❌ Update error: \(err)")
                        return false
                    }
                    let success = update["userBookRead"] != nil
                    print(success ? "✅ Successfully updated reading date" : "❌ Update failed - no userBookRead in response")
                    return success
                } else {
                    print("❌ Could not parse response data")
                }
            }
        } catch {
            print("❌ Update failed with error: \(error)")
            return false
        }
        print("❌ Update failed - unknown reason")
        return false
    }
    
    static func insertReadingDate(userBookId: Int, startedAt: String, editionId: Int?) async -> Int? {
        print("📅 insertReadingDate called - userBookId: \(userBookId), startedAt: \(startedAt), editionId: \(editionId ?? -1)")
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ API key is empty")
            return nil
        }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid URL")
            return nil
        }
        
        // Strategy: Only reuse an existing read entry if it's incomplete (no finished date)
        // Otherwise, always create a new read entry for a new reading session
        
        // Try to find an existing incomplete read (no finished date)
        print("🔍 Looking for incomplete reads for userBookId: \(userBookId)")
        let existingReads = await fetchReadingDates(userBookId: userBookId)
        print("📚 Found \(existingReads.count) existing reads")
        
        // Check if there's an incomplete read (no finished date)
        if let incompleteRead = existingReads.first(where: { $0.finishedAt == nil }) {
            print("♻️ Found incomplete read with id: \(incompleteRead.id), updating it...")
            let success = await updateReadingDate(
                readId: incompleteRead.id,
                startedAt: startedAt,
                finishedAt: nil,
                editionId: editionId
            )
            return success ? incompleteRead.id : nil
        }
        
        // No incomplete read found - we need to create a new one for this new reading session
        print("➕ All existing reads are complete, creating new read entry...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        var object: [String: Any] = [
            "user_book_id": userBookId,
            "started_at": startedAt
        ]
        if let eid = editionId, eid > 0 { object["edition_id"] = eid }
        
        // Try Hasura's direct insert mutation format
        let mutation = """
        mutation InsertUserBookRead($object: user_book_reads_insert_input!) {
          insert_user_book_reads_one(object: $object) {
            id
            started_at
            finished_at
            user_book_id
            edition_id
          }
        }
        """
        let body: [String: Any] = [
            "operationName": "InsertUserBookRead",
            "query": mutation,
            "variables": ["object": object]
        ]
        
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = bodyData
            print("🚀 Sending insert request with operation name...")
            print("📦 Body: \(String(data: bodyData, encoding: .utf8) ?? "invalid")")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let responseString = String(data: data, encoding: .utf8) ?? "invalid"
            print("📨 Response: \(responseString)")
            
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                    print("❌ GraphQL errors: \(errs)")
                    // If insert fails, we need to create via status manipulation
                    print("🔄 Trying alternative: creating new read via status manipulation...")
                    return await createNewReadViaStatusUpdate(userBookId: userBookId, startedAt: startedAt, editionId: editionId)
                }
                if let dataDict = root["data"] as? [String: Any],
                   let inserted = dataDict["insert_user_book_reads_one"] as? [String: Any],
                   let id = inserted["id"] as? Int {
                    print("✅ Successfully inserted reading date with id: \(id)")
                    return id
                }
            }
        } catch {
            print("❌ Insert failed with error: \(error)")
        }
        
        print("🔄 Standard insert failed, trying alternative method...")
        return await createNewReadViaStatusUpdate(userBookId: userBookId, startedAt: startedAt, editionId: editionId)
    }
    
    // Alternative method: Create a NEW read entry by temporarily changing status
    // This creates a completely new reading session, not reusing existing ones
    private static func createNewReadViaStatusUpdate(userBookId: Int, startedAt: String, editionId: Int?) async -> Int? {
        print("🔄 createNewReadViaStatusUpdate called - creating a brand new read entry")
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        
        // Fetch the current status to restore it later
        print("🔍 Fetching current status for userBookId: \(userBookId)")
        let originalStatus = await fetchUserBookStatus(userBookId: userBookId)
        print("📊 Original status: \(originalStatus ?? -1)")
        
        // Get count of existing reads before we create a new one
        let existingReadsCountBefore = await fetchReadingDates(userBookId: userBookId).count
        print("📊 Existing reads before: \(existingReadsCountBefore)")
        
        // Change status to "want to read" (1) first, then to "reading" (2)
        // This should force creation of a NEW read entry
        print("🔄 Step 1: Changing to 'Want to Read' to reset...")
        _ = await updateUserBookStatus(userBookId: userBookId, statusId: 1)
        try? await Task.sleep(nanoseconds: 300_000_000) // Wait 0.3s
        
        print("🔄 Step 2: Changing to 'Reading' to create new read entry...")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        var updateObject: [String: Any] = [
            "status_id": 2
        ]
        if let eid = editionId, eid > 0 { updateObject["edition_id"] = eid }
        
        let mutation = """
        mutation UpdateUserBookToReading($id: Int!, $object: UserBookUpdateInput!) {
          update_user_book(id: $id, object: $object) {
            error
            user_book {
              id
              status_id
            }
          }
        }
        """
        let body: [String: Any] = [
            "operationName": "UpdateUserBookToReading",
            "query": mutation,
            "variables": ["id": userBookId, "object": updateObject]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            let responseString = String(data: data, encoding: .utf8) ?? "invalid"
            print("📨 Status update response: \(responseString)")
        } catch {
            print("❌ Status update failed: \(error)")
        }
        
        // Wait for the new read entry to be created
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s
        
        // Fetch reads again to find the NEW one
        let allReads = await fetchReadingDates(userBookId: userBookId)
        print("📊 Total reads after: \(allReads.count)")
        
        // Find the newly created read (should be the one without a finished date)
        if let newRead = allReads.first(where: { $0.finishedAt == nil }) {
            print("✅ Found new read entry with id: \(newRead.id), updating start date...")
            
            // Update it with our desired start date
            let success = await updateReadingDate(
                readId: newRead.id,
                startedAt: startedAt,
                finishedAt: nil,
                editionId: editionId
            )
            
            // Restore original status if needed
            if let status = originalStatus, status != 2 {
                print("🔄 Restoring original status: \(status)")
                _ = await updateUserBookStatus(userBookId: userBookId, statusId: status)
            }
            
            return success ? newRead.id : nil
        }
        
        print("❌ Could not find newly created read entry")
        return nil
    }
    
    // Old method: Find and reuse existing read entry (kept for backward compatibility)
    private static func createReadViaStatusUpdate(userBookId: Int, startedAt: String, editionId: Int?) async -> Int? {
        print("🔄 createReadViaStatusUpdate called")
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        
        // First, fetch the current status to restore it later
        print("🔍 Fetching current status for userBookId: \(userBookId)")
        let originalStatus = await fetchUserBookStatus(userBookId: userBookId)
        print("📊 Original status: \(originalStatus ?? -1)")
        
        // Only change status if it's not already "reading" or "read"
        let needsStatusChange = originalStatus != 2 && originalStatus != 3
        
        if needsStatusChange {
            // Update to status 2 (reading) temporarily to create a read entry
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            
            var updateObject: [String: Any] = [
                "status_id": 2
            ]
            if let eid = editionId, eid > 0 { updateObject["edition_id"] = eid }
            
            let mutation = """
            mutation UpdateUserBookToReading($id: Int!, $object: UserBookUpdateInput!) {
              update_user_book(id: $id, object: $object) {
                error
                user_book {
                  id
                  status_id
                }
              }
            }
            """
            let body: [String: Any] = [
                "operationName": "UpdateUserBookToReading",
                "query": mutation,
                "variables": ["id": userBookId, "object": updateObject]
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, _) = try await URLSession.shared.data(for: request)
                let responseString = String(data: data, encoding: .utf8) ?? "invalid"
                print("📨 Status update response: \(responseString)")
            } catch {
                print("❌ Status update failed: \(error)")
            }
            
            // Wait for the read entry to be created
            try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s
        }
        
        // Fetch the reads to get the read ID
        let reads = await fetchReadingDates(userBookId: userBookId)
        if let latestRead = reads.first {
            print("✅ Found read entry with id: \(latestRead.id), updating start date...")
            
            // Update it with our desired start date
            let success = await updateReadingDate(
                readId: latestRead.id,
                startedAt: startedAt,
                finishedAt: nil,
                editionId: editionId
            )
            
            // Restore original status if we changed it
            if needsStatusChange, let status = originalStatus {
                print("🔄 Restoring original status: \(status)")
                _ = await updateUserBookStatus(userBookId: userBookId, statusId: status)
            }
            
            return success ? latestRead.id : nil
        }
        
        return nil
    }
    
    // Helper function to fetch current user_book status
    private static func fetchUserBookStatus(userBookId: Int) async -> Int? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id } }) {
            status_id
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["id": userBookId]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let userBooks = dataDict["user_books"] as? [[String: Any]],
               let first = userBooks.first,
               let statusId = first["status_id"] as? Int {
                return statusId
            }
        } catch {
            return nil
        }
        return nil
    }
    
    static func deleteReadingDate(readId: Int) async -> Bool {
        print("🗑️ deleteReadingDate called - readId: \(readId)")
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ API key is empty")
            return false
        }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid URL")
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let mutation = """
        mutation DeleteUserBookReadMutation($id: Int!) {
          deleteResponse: delete_user_book_read(id: $id) {
            error
            id
          }
        }
        """
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["id": readId],
            "operationName": "DeleteUserBookReadMutation"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("🚀 Sending delete request...")
            if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                print("📦 Body: \(bodyString)")
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            if let responseString = String(data: data, encoding: .utf8) {
                print("📨 Response: \(responseString)")
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                    print("❌ GraphQL errors: \(errs)")
                    return false
                }
                if let dataDict = root["data"] as? [String: Any],
                   let deleteResponse = dataDict["deleteResponse"] as? [String: Any] {
                    // Check if there's an error field
                    if let error = deleteResponse["error"] as? String, !error.isEmpty {
                        print("❌ Delete error: \(error)")
                        return false
                    }
                    // Check if we got an id back
                    let success = deleteResponse["id"] != nil
                    print(success ? "✅ Successfully deleted" : "❌ No id in delete response")
                    return success
                }
            }
        } catch {
            print("❌ Exception: \(error)")
            return false
        }
        print("❌ Unexpected response format")
        return false
    }
}
