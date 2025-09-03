import Foundation
import UIKit

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
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isbn10 = "isbn_10"
        case isbn13 = "isbn_13"
        case pages
        case publisher
        case image
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
}

// MARK: - Image Cache
class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSData>()
    
    private init() {
        // Conservative cache limits for widget extension
        cache.countLimit = 5 // Increased limit for multiple books
        cache.totalCostLimit = 5 * 1024 * 1024 // Max 5MB
    }
    
    func setImageData(_ data: Data, forKey key: String) {
        cache.setObject(data as NSData, forKey: key as NSString)
    }
    func imageData(forKey key: String) -> Data? {
        return cache.object(forKey: key as NSString) as Data?
    }
}

// Extension to clear cache
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
        guard !normalized.isEmpty else { return ""
        }
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
          if let resized = resizeImageToFitWidget(data) {
              ImageCache.shared.setImageData(resized, forKey: urlString)
              return resized
          }
          return nil
      } catch {
          print("❌ Image download error: \(error)")
          return nil
      }
  }
  
  private static func resizeImageToFitWidget(_ imageData: Data) -> Data? {
      guard let image = UIImage(data: imageData) else { return nil }
      let maxWidth: CGFloat = 400
      if image.size.width <= maxWidth { return image.jpegData(compressionQuality: 0.8) }
      let scale = maxWidth / image.size.width
      let newSize = CGSize(width: maxWidth, height: image.size.height * scale)
      UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
      defer { UIGraphicsEndImageContext() }
      image.draw(in: CGRect(origin: .zero, size: newSize))
      return UIGraphicsGetImageFromCurrentImageContext()?.jpegData(compressionQuality: 0.8)
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
              let displayTitle: String
              if let editionTitle = userBook.edition?.title, !editionTitle.isEmpty {
                  displayTitle = editionTitle
                  print("✅ Using edition title: \(editionTitle)")
              } else {
                  displayTitle = bookData.title
                  print("✅ Using book title: \(displayTitle)")
              }
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
                  print("✅ Using edition cover for: \(displayTitle)")
              } else if let bookImageUrl = bookData.image?.url, !bookImageUrl.isEmpty {
                  imageUrl = bookImageUrl
                  print("✅ Using book cover for: \(displayTitle)")
              } else {
                  imageUrl = nil
                  print("⚠️ No cover image for: \(displayTitle)")
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
                  currentPage: currentPage,
                  bookId: bookData.id,
                  userBookId: userBook.id,
                  editionId: userBook.editionId,
                  originalTitle: bookData.title
              )
              
              print("📚 Created book - Title: \(displayTitle), UserBookId: \(userBook.id ?? -1), BookId: \(bookData.id ?? -1), EditionId: \(userBook.editionId ?? -1)")
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
      print("📝 Inserting book read - UserBookId: \(userBookId), Page: \(page), EditionId: \(editionId ?? -1)")
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
          print("📤 Sending read mutation: \(String(data: body, encoding: .utf8) ?? "")")
          let (data, response) = try await URLSession.shared.data(for: request)
          if let http = response as? HTTPURLResponse { print("📥 Insert user_book_read HTTP Status: \(http.statusCode)") }
          if let raw = String(data: data, encoding: .utf8) { print("📥 Insert user_book_read Raw: \(raw)") }
          if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
              if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty {
                  print("❌ Insert user_book_read GraphQL errors: \(errs)")
                  return false
              }
              if let dataDict = json["data"] as? [String: Any],
                 let insert = dataDict["insert_user_book_read"] as? [String: Any] {
                  if let err = insert["error"] as? String, !err.isEmpty {
                      print("❌ Insert user_book_read error: \(err)")
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
                print("❌ fetchReadingStats GraphQL errors: \(errs)")
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
            print("❌ fetchReadingStats error: \(error)")
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
                let count = reads.count
                print("🔢 Self-heal: counted \(count) finished reads (including rereads) in \(startDate)...\(endDate) for user \(userId)")
                return count
            } else {
                let uniqueBookIds = Set(reads.compactMap { $0["user_book_id"] as? Int })
                let count = uniqueBookIds.count
                print("🔢 Self-heal: counted \(count) unique finished books in \(startDate)...\(endDate) for user \(userId) (reads rows: \(reads.count))")
                return count
            }
        } catch {
            print("❌ countFinishedBooks error: \(error)")
            return 0
        }
    }
    
    static func fetchReadingGoals() async -> [ReadingGoal] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key configured for reading goals")
            return []
        }
        
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else {
            print("❌ Could not get user ID for reading goals")
            return []
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query GetReadingGoals($userId: Int!) {
            activities(where: {user_id: {_eq: $userId}, event: {_eq: "GoalActivity"}}, order_by: {created_at: desc}, limit: 500) {
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
            let gqlResponse = try JSONDecoder().decode(GraphQLActivitiesResponse.self, from: data)
            
            if let errors = gqlResponse.errors {
                for error in errors {
                    print("❌ GraphQL Reading Goals API Error: \(error.message)")
                }
                return []
            }
            
            guard let activities = gqlResponse.data?.activities else {
                print("❌ No activities data returned for reading goals")
                return []
            }
            
            print("📥 Reading Goals: fetched \(activities.count) GoalActivity rows for user_id=\(userId)")
            
            let debugGoalId = 33007
            let debugMatches = activities.compactMap { act -> (String, ReadingGoal)? in
                guard act.event == "GoalActivity", let g = act.data?.goal, g.id == debugGoalId else { return nil }
                return (act.created_at ?? "nil", g)
            }
            if !debugMatches.isEmpty {
                print("🔎 Debug Goal \(debugGoalId): found \(debugMatches.count) activity snapshots:")
                for (ts, g) in debugMatches {
                    print("   • created_at=\(ts), progress=\(g.progress), percent=\(Int(g.percentComplete * 100))%, start=\(g.startDate), end=\(g.endDate)")
                }
            } else {
                print("🔎 Debug Goal \(debugGoalId): no snapshots found in fetched activities.")
            }
            
            var latestByGoal: [Int: (goal: ReadingGoal, createdAt: Date, createdAtRaw: String)] = [:]
            for activity in activities {
                guard activity.event == "GoalActivity",
                      let goal = activity.data?.goal else {
                    continue
                }
                let createdAtRaw = activity.created_at ?? ""
                let createdAtDate = parseAPITimestamp(createdAtRaw) ?? .distantPast
                if let existing = latestByGoal[goal.id] {
                    if createdAtDate > existing.createdAt {
                        latestByGoal[goal.id] = (goal, createdAtDate, createdAtRaw)
                    }
                } else {
                    latestByGoal[goal.id] = (goal, createdAtDate, createdAtRaw)
                }
            }
            
            if let chosen = latestByGoal[debugGoalId] {
                print("✅ Chosen snapshot for Goal \(debugGoalId): created_at=\(chosen.createdAtRaw), progress=\(chosen.goal.progress), percent=\(Int(chosen.goal.percentComplete * 100))%")
            }
            
            var goals = latestByGoal.values
                .map { $0.goal }
                .sorted { ($0.endDate, $0.id) > ($1.endDate, $1.id) }
            
            print("✅ Extracted \(goals.count) unique reading goals (latest snapshot per goal).")
            
            if enableGoalSelfHeal {
                print("🛠️ Self-heal enabled: reconciling goal progress using finished books count when higher.")
                var healed: [ReadingGoal] = []
                for g in goals {
                    if g.metric.lowercased() == "book" {
                        let counted = await countFinishedBooks(userId: userId, startDate: g.startDate, endDate: g.endDate)
                        if counted > g.progress {
                            let newPercent = min(1.0, Double(counted) / Double(max(g.goal, 1)))
                            print("✅ Self-heal applied for goal \(g.id): snapshot=\(g.progress), counted=\(counted) -> using \(counted) (\(Int(newPercent * 100))%)")
                            if let healedGoal = healGoalProgress(original: g, newProgress: counted, newPercent: newPercent) {
                                healed.append(healedGoal)
                                continue
                            }
                        } else {
                            print("ℹ️ Self-heal not needed for goal \(g.id): snapshot=\(g.progress), counted=\(counted)")
                        }
                    }
                    healed.append(g)
                }
                goals = healed
            } else {
                print("ℹ️ Self-heal disabled: using snapshot progress as-is.")
            }
            
            return goals
            
        } catch {
            print("❌ GraphQL Reading Goals API Error: \(error)")
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
            print("❌ healGoalProgress error: \(error)")
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
            // Try yyyy-MM-dd first (GraphQL date)
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: s) { return d }
            // Fallback to ISO8601 timestamps if server ever returns that
            return parseAPITimestamp(s)
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ fetchReadingHistory GraphQL errors: \(errs)")
                return []
            }
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
                
                // Title: prefer edition title, else book title
                let editionDict = userBook["edition"] as? [String: Any]
                let editionTitle = editionDict?["title"] as? String
                let bookDict = userBook["book"] as? [String: Any]
                let bookTitle = (bookDict?["title"] as? String) ?? "Unknown Title"
                let displayTitle = (editionTitle?.isEmpty == false) ? editionTitle! : bookTitle
                
                // Author: first contribution author name
                var author = "Unknown Author"
                if let contributions = bookDict?["contributions"] as? [[String: Any]],
                   let first = contributions.first,
                   let a = (first["author"] as? [String: Any])?["name"] as? String,
                   !a.isEmpty {
                    author = a
                }
                
                // Cover: prefer edition image, else book image
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
                    coverImageData: coverData
                )
                results.append(entry)
            }
            
            return results
        } catch {
            print("❌ fetchReadingHistory error: \(error)")
            return []
        }
    }
}

// MARK: - Finish book helpers
extension HardcoverService {
    /// Marks a book as finished and ensures finished_at is set to today's date (UTC).
    /// Also sets progress_pages to totalPages if provided, otherwise currentPage if provided.
    /// Optionally sets a rating (1.0–5.0, half-star increments allowed).
    static func finishBook(userBookId: Int, editionId: Int?, totalPages: Int?, currentPage: Int?, rating: Double?) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        print("📗 finishBook: userBookId=\(userBookId), editionId=\(editionId ?? -1), totalPages=\(totalPages ?? -1), currentPage=\(currentPage ?? -1), rating=\(String(describing: rating))")
        
        // If we have a rating, update status and rating in ONE mutation to avoid server-side overwrites/policies.
        var statusOK = true
        if let value = rating {
            let clamped = max(0.5, min(5.0, (round(value * 2) / 2)))
            statusOK = await updateUserBook(userBookId: userBookId, statusId: 3, rating: clamped)
        } else {
            statusOK = await updateUserBookStatus(userBookId: userBookId, statusId: 3)
        }
        if !statusOK {
            print("❌ finishBook: failed to update status/rating")
            return false
        }
        
        let today = utcDateString()
        var finishedOK = false
        if let readId = await fetchLatestReadId(userBookId: userBookId) {
            // First try to set finished_at on the latest read
            finishedOK = await updateReadFinishedAt(readId: readId, finishedAt: today)
            print("ℹ️ finishBook: updateReadFinishedAt -> \(finishedOK)")
        }
        if !finishedOK {
            // Insert a finished read if no existing read or update failed
            let pages: Int? = totalPages ?? currentPage
            finishedOK = await insertFinishedRead(userBookId: userBookId, editionId: editionId, pages: pages, finishedAt: today)
            print("ℹ️ finishBook: insertFinishedRead -> \(finishedOK)")
        }
        if !finishedOK {
            print("❌ finishBook: could not set finished_at")
            return false
        }
        return true
    }
    
    /// Updates both status_id and rating in one mutation (sends rating only when non-nil).
    static func updateUserBook(userBookId: Int, statusId: Int, rating: Double?) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Build the object dictionary without rating when rating == nil so we don't clear existing rating inadvertently.
        var object: [String: Any] = ["status_id": statusId]
        if let r = rating {
            object["rating"] = r
        }
        
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
            "variables": [
                "id": userBookId,
                "object": object
            ]
        ]
        
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            if let raw = String(data: bodyData, encoding: .utf8) {
                print("📤 updateUserBook body: \(raw)")
            }
            request.httpBody = bodyData
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                    print("❌ updateUserBook GraphQL errors: \(errs)")
                    return false
                }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["update_user_book"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty {
                        print("❌ update_user_book error: \(err)")
                        return false
                    }
                    if let ub = update["user_book"] as? [String: Any] {
                        print("✅ updateUserBook success: \(ub)")
                        return true
                    }
                    return false
                }
            }
        } catch {
            print("❌ updateUserBook error: \(error)")
        }
        return false
    }
    
    /// Updates rating on user_book. Passing nil will clear rating.
    static func updateUserBookRating(userBookId: Int, rating: Double?) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // GraphQL mutation to update rating on a user_book
        let mutation = """
        mutation ($id: Int!, $rating: float8) {
          update_user_book(id: $id, object: { rating: $rating }) {
            error
            user_book { id rating }
          }
        }
        """
        let vars: [String: Any] = ["id": userBookId, "rating": rating as Any]
        let body: [String: Any] = [
            "query": mutation,
            "variables": vars
        ]
        
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            if let raw = String(data: bodyData, encoding: .utf8) {
                print("📤 updateUserBookRating body: \(raw)")
            }
            request.httpBody = bodyData
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                    print("❌ updateUserBookRating GraphQL errors: \(errs)")
                    return false
                }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["update_user_book"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty {
                        print("❌ update_user_book error: \(err)")
                        return false
                    }
                    if let ub = update["user_book"] as? [String: Any] {
                        print("✅ updateUserBookRating success: \(ub)")
                        return true
                    }
                    return false
                }
            }
        } catch {
            print("❌ updateUserBookRating error: \(error)")
        }
        return false
    }
    
    private static func fetchLatestReadId(userBookId: Int) async -> Int? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "query": """
            query ($id: Int!) {
              user_book_reads(where: { user_book_id: { _eq: $id } }, order_by: { id: desc }, limit: 1) {
                id
                finished_at
              }
            }
            """,
            "variables": ["id": userBookId]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let reads = dataDict["user_book_reads"] as? [[String: Any]],
               let latest = reads.first,
               let id = latest["id"] as? Int {
                return id
            }
        } catch {
            print("❌ fetchLatestReadId error: \(error)")
        }
        return nil
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
            print("❌ updateReadFinishedAt error: \(error)")
        }
        return false
    }
    
    private static func insertFinishedRead(userBookId: Int, editionId: Int?, pages: Int?, finishedAt: String) async -> Bool {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        var vars: [String: Any] = [
            "id": userBookId,
            "finishedAt": finishedAt
        ]
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
        let body: [String: Any] = [
            "query": mutation,
            "variables": vars
        ]
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
            print("❌ insertFinishedRead error: \(error)")
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
