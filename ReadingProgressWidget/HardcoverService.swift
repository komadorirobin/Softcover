import Foundation
import UIKit
import ImageIO
import MobileCoreServices

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
  
  static func fetchCurrentlyReading(forWidget: Bool = false) async -> [BookProgress] {
      guard !HardcoverConfig.apiKey.isEmpty else { return [] }
      if forWidget, let snapshot = LibrarySnapshot.load(status: 2, maxAge: 300), !snapshot.stale {
          var books = Array(snapshot.books.prefix(10))
          await loadImagesForWidgets(books: &books)
          return books
      }
      do {
          let page = try await LibraryAPI.page(status: 2, limit: forWidget ? 10 : 50)
          var books = page.books
          if !forWidget { LibrarySnapshot.save(books, status: 2, complete: !page.hasMore) }
          if forWidget { await loadImagesForWidgets(books: &books) }
          return books
      } catch {
          HardcoverReadScope.failure?.record(error)
          var books = LibrarySnapshot.load(status: 2)?.books ?? []
          if forWidget { books = Array(books.prefix(10)); await loadImagesForWidgets(books: &books) }
          return books
      }
  }

  static func fetchWantToRead(limit: Int, forWidget: Bool = false) async -> [BookProgress] {
      do {
          let page = try await LibraryAPI.page(status: 1, limit: limit)
          var books = page.books
          if forWidget { await loadImagesForWidgets(books: &books) }
          return books
      } catch {
          HardcoverReadScope.failure?.record(error)
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
  
  // Helper function to load images for widgets
  static func loadImagesForWidgets(books: inout [BookProgress]) async {
      await withTaskGroup(of: (Int, Data?).self) { group in
          for (index, book) in books.prefix(4).enumerated() {
              // Skip if already has image data
              if book.coverImageData != nil { continue }
              guard let urlString = book.coverImageUrl else { continue }
              
              group.addTask {
                  let imageData = await fetchAndResizeImage(from: urlString)
                  return (index, imageData)
              }
          }
          
          for await (index, imageData) in group {
              if let data = imageData {
                  books[index].coverImageData = data
              }
          }
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
  
  // MARK: - Local Progress Timestamps
  /// Saves a local timestamp when progress is updated for a book
  private static func saveLocalProgressTimestamp(forUserBookId userBookId: Int) {
      let timestamp = Date().timeIntervalSince1970
      AppGroup.defaults.set(timestamp, forKey: "progressTimestamp_\(userBookId)")
      print("💾 Saved local progress timestamp for userBookId \(userBookId): \(timestamp)")
  }
  
  /// Gets the local progress timestamp for a book
  private static func getLocalProgressTimestamp(forUserBookId userBookId: Int) -> TimeInterval? {
      let timestamp = AppGroup.defaults.double(forKey: "progressTimestamp_\(userBookId)")
      return timestamp > 0 ? timestamp : nil
  }
  
  /// Saves the last known progress for a book
  private static func saveLastKnownProgress(forUserBookId userBookId: Int, progress: Int) {
      AppGroup.defaults.set(progress, forKey: "lastProgress_\(userBookId)")
  }
  
  /// Gets the last known progress for a book
  private static func getLastKnownProgress(forUserBookId userBookId: Int) -> Int? {
      let progress = AppGroup.defaults.integer(forKey: "lastProgress_\(userBookId)")
      return progress > 0 ? progress : nil
  }
  
  /// Checks if progress has changed and updates timestamp if needed
  private static func updateTimestampIfProgressChanged(forUserBookId userBookId: Int, currentProgress: Int) {
      guard currentProgress > 0 else { return }
      
      let lastProgress = getLastKnownProgress(forUserBookId: userBookId)
      
      if let lastProgress = lastProgress, lastProgress != currentProgress {
          // Progress has changed since last fetch - update timestamp
          saveLocalProgressTimestamp(forUserBookId: userBookId)
          print("📈 Progress changed for userBookId \(userBookId): \(lastProgress) → \(currentProgress), updating timestamp")
      }
      
      // Save current progress for next comparison
      saveLastKnownProgress(forUserBookId: userBookId, progress: currentProgress)
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
  
  
  static func fetchEditions(for bookId: Int) async -> [Edition] {
      guard !HardcoverConfig.apiKey.isEmpty else { HardcoverReadScope.failure?.record(HardcoverNetworkError.signIn); return [] }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let query = LibraryAPI.editionsQuery
      
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: [
              "query": query,
              "variables": ["bookId": bookId]
          ])
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
          let gqlResponse = try JSONDecoder().decode(GraphQLEditionsResponse.self, from: data)
          if let errors = gqlResponse.errors {
              for error in errors {
                  print("❌ GraphQL Editions API Error: \(error.message)")
              }
              return []
          }
          guard let editions = gqlResponse.data?.editions else {
              HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
              return []
          }
          return editions
      } catch {
          print("❌ GraphQL Editions API Error: \(error)")
          HardcoverReadScope.failure?.record(error)
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
        let (data, response) = try await HardcoverHTTP.shared.data(for: request)
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
          let (uData, _) = try await HardcoverHTTP.shared.data(for: request)
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
  
  static func insertBookRead(userBookId: Int, page: Int, editionId: Int? = nil, isAudiobook: Bool = false) async -> Bool {
      print("📝 Updating book read progress - UserBookId: \(userBookId), \(isAudiobook ? "Seconds" : "Page"): \(page), EditionId: \(editionId ?? -1)")
      guard !HardcoverConfig.apiKey.isEmpty else { 
          print("❌ API key is empty")
          return false 
      }
      guard page >= 0 else { 
          print("❌ Invalid \(isAudiobook ? "seconds" : "page") number: \(page)")
          return false 
      }
      
      // First, try to find the latest user_book_read for this user_book
      if let latestRead = await fetchLatestReadId(userBookId: userBookId) {
          // Update the existing read, passing started_at so Hardcover generates
          // the correct "Is X% done with" activity feed entry (fixes #8).
          let startedAtDisplay = latestRead.startedAt ?? "nil"
          print("📝 Updating existing read ID: \(latestRead.id), startedAt: \(startedAtDisplay)")
          let success = await updateExistingBookRead(readId: latestRead.id, page: page, editionId: editionId, isAudiobook: isAudiobook, startedAt: latestRead.startedAt)
          if success {
              print("✅ Successfully updated existing read")
              // Touch user_book to trigger activity feed entry
              await touchUserBook(userBookId: userBookId)
              // Save local timestamp for sorting
              saveLocalProgressTimestamp(forUserBookId: userBookId)
              return true
          }
          print("⚠️ Failed to update existing read, will try creating new one")
      } else {
          print("⚠️ No existing read found")
      }
      
      // If update failed or no existing read, create new one
      print("📝 Creating new book read")
      let success = await createNewBookRead(userBookId: userBookId, page: page, editionId: editionId, isAudiobook: isAudiobook)
      if success {
          // Touch user_book to trigger activity feed entry
          await touchUserBook(userBookId: userBookId)
          // Save local timestamp for sorting
          saveLocalProgressTimestamp(forUserBookId: userBookId)
      }
      return success
  }
  
  private static func fetchAnyReadId(userBookId: Int) async -> Int? {
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let query = """
      query ($id: Int!) {
        user_book_reads(where: { user_book_id: { _eq: $id } }, order_by: { id: desc }, limit: 1) {
          id
        }
      }
      """
      
      let body: [String: Any] = [
          "query": query,
          "variables": ["id": userBookId]
      ]
      
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
          
          guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataDict = json["data"] as? [String: Any],
                let reads = dataDict["user_book_reads"] as? [[String: Any]],
                let latest = reads.first,
                let readId = latest["id"] as? Int else {
              print("⚠️ No read found for userBookId: \(userBookId)")
              return nil
          }
          print("✅ Found read ID: \(readId)")
          return readId
      } catch {
          print("❌ fetchAnyReadId error: \(error)")
          return nil
      }
  }
  
  private static func fetchLatestReadId(userBookId: Int) async -> (id: Int, startedAt: String?)? {
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
          
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
          let startedAt = latest["started_at"] as? String
          let startedAtDisplay = startedAt ?? "nil"
          print("✅ Found ongoing read ID: \(readId), startedAt: \(startedAtDisplay)")
          return (id: readId, startedAt: startedAt)
      } catch {
          print("❌ fetchLatestReadId error: \(error)")
          return nil
      }
  }
  
  private static func updateExistingBookRead(readId: Int, page: Int, editionId: Int?, isAudiobook: Bool = false, startedAt: String? = nil) async -> Bool {
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      var datesReadDict: [String: Any] = [:]
      if isAudiobook {
          datesReadDict["progress_seconds"] = page
      } else {
          datesReadDict["progress_pages"] = page
      }
      if let eid = editionId {
          datesReadDict["edition_id"] = eid
      }
      if let sa = startedAt {
          datesReadDict["started_at"] = sa
      }
      
      let mutation = """
      mutation ($id: Int!, $object: DatesReadInput!) {
          update_user_book_read(id: $id, object: $object) {
              error
              user_book_read { id progress_pages progress_seconds edition_id }
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
          let (data, response) = try await HardcoverHTTP.shared.data(for: request)
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
  
  /// Touches the user_book record by setting user_date to today.
  /// This triggers an activity feed entry. Combined with started_at
  /// in the read update, it produces "Is X% done with" (fixes #8).
  private static func touchUserBook(userBookId: Int) async {
      guard !HardcoverConfig.apiKey.isEmpty else { return }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
  
      let df = DateFormatter()
      df.calendar = Calendar(identifier: .gregorian)
      df.locale = Locale(identifier: "en_US_POSIX")
      df.timeZone = TimeZone(secondsFromGMT: 0)
      df.dateFormat = "yyyy-MM-dd"
      let today = df.string(from: Date())

      let body: [String: Any] = [
          "query": """
          mutation ($id: Int!, $object: UserBookUpdateInput!) {
            update_user_book(id: $id, object: $object) {
              error
              user_book { id status_id }
            }
          }
          """,
          "variables": ["id": userBookId, "object": ["user_date": today]]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
          if let raw = String(data: data, encoding: .utf8) {
              print("touchUserBook response: \(raw)")
          }
      } catch {
          print("touchUserBook error: \(error)")
      }
  }

  private static func createNewBookRead(userBookId: Int, page: Int, editionId: Int?, isAudiobook: Bool = false) async -> Bool {
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
      
      let progressField = isAudiobook ? "progress_seconds" : "progress_pages"
      let progressVar = isAudiobook ? "$seconds" : "$pages"
      
      let mutation = """
      mutation InsertUserBookRead($id: Int!, \(isAudiobook ? "$seconds" : "$pages"): Int, $editionId: Int, $startedAt: date) {
          insert_user_book_read(user_book_id: $id, user_book_read: {
              \(progressField): \(progressVar),
              edition_id: $editionId,
              started_at: $startedAt,
          }) {
              error
              user_book_read { id progress_pages progress_seconds edition_id started_at finished_at }
          }
      }
      """
      var variables: [String: Any] = [
          "id": userBookId,
          isAudiobook ? "seconds" : "pages": page,
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
          let (data, response) = try await HardcoverHTTP.shared.data(for: request)
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
  
  static func updateProgress(userBookId: Int, editionId: Int?, page: Int, isAudiobook: Bool = false) async -> Bool {
      // For audiobooks, 'page' is actually minutes, so convert to seconds
      let progressValue = isAudiobook ? (page * 60) : page
      return await insertBookRead(userBookId: userBookId, page: progressValue, editionId: editionId, isAudiobook: isAudiobook)
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
          results
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
          let resp = try JSONDecoder().decode(GraphQLSearchResponse.self, from: data)
          if let errors = resp.errors, !errors.isEmpty {
              errors.forEach { print("❌ GraphQL Search Error: \($0.message)") }
              return []
          }
          if let resultBooks = resp.data?.search?.results?.map(\.hydratedBook), !resultBooks.isEmpty {
              return resultBooks
          }
          guard let ids = resp.data?.search?.ids, !ids.isEmpty else { return [] }
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
          cached_contributors
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
          let (data, response) = try await HardcoverHTTP.shared.data(for: request)
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
  
  static func updateUserBookStatus(userBookId: Int, statusId: Int, userDate: String? = nil) async -> Bool {
      guard !HardcoverConfig.apiKey.isEmpty else { return false }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      var object: [String: Any] = ["status_id": statusId]
      if let date = userDate { object["user_date"] = date }
      
      let body: [String: Any] = [
          "query": """
          mutation ($id: Int!, $object: UserBookUpdateInput!) {
            update_user_book(id: $id, object: $object) {
              error
              user_book { id status_id }
            }
          }
          """,
          "variables": ["id": userBookId, "object": object]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
  
  private static func fetchUserBookDate(userBookId: Int) async -> String? {
      guard !HardcoverConfig.apiKey.isEmpty else { return nil }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      let body: [String: Any] = [
          "query": """
          query GetUserBookDate($id: Int!) {
            user_books(where: { id: { _eq: $id }}) {
              user_date
            }
          }
          """,
          "variables": ["id": userBookId]
      ]
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
          if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
             let dataDict = root["data"] as? [String: Any],
             let userBooks = dataDict["user_books"] as? [[String: Any]],
             let first = userBooks.first,
             let userDate = first["user_date"] as? String {
              return userDate
          }
      } catch {
          print("❌ fetchUserBookDate error: \(error)")
      }
      return nil
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
          let resp = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data)
          if let errs = resp.errors, !errs.isEmpty { return nil }
          return resp.data?.user_books?.first
      } catch {
          print("❌ fetchUserBook error: \(error)")
          return nil
      }
  }
  
  // Fetch user_book status for a given bookId
  // Returns tuple: (statusId, userBookId) or nil if not in library
  static func fetchBookStatus(bookId: Int) async -> (statusId: Int, userBookId: Int)? {
      guard !HardcoverConfig.apiKey.isEmpty else { return nil }
      guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { return nil }
      guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
      
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
      
      let body: [String: Any] = [
          "query": """
          query GetBookStatus($userId: Int!, $bookId: Int!) {
            user_books(where: { user_id: { _eq: $userId }, book_id: { _eq: $bookId } }, limit: 1) {
              id
              status_id
            }
          }
          """,
          "variables": ["userId": userId, "bookId": bookId]
      ]
      
      do {
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
          if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
             let dataDict = root["data"] as? [String: Any],
             let userBooks = dataDict["user_books"] as? [[String: Any]],
             let first = userBooks.first,
             let statusId = first["status_id"] as? Int,
             let userBookId = first["id"] as? Int {
              return (statusId: statusId, userBookId: userBookId)
          }
      } catch {
          print("❌ fetchBookStatus error: \(error)")
      }
      return nil
  }
  
  static func fetchAccountPrivacySettingId() async -> Int? {
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
          let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
        do {
            let user = try await LibraryAPI.identity()
            return await fetchUserReadingGoals(username: user.username)
        } catch {
            HardcoverReadScope.failure?.record(error)
            return []
        }
    }
    
    private static func getCurrentUsername(apiKey: String) async -> String? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.headerValue(for: apiKey), forHTTPHeaderField: "Authorization")
        
        let query = """
        query {
            me {
                username
            }
        }
        """
        
        let body: [String: Any] = ["query": query]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = bodyData
        
        do {
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let me = dataObj["me"] as? [[String: Any]],
               let firstMe = me.first,
               let username = firstMe["username"] as? String {
                return username
            }
        } catch {
            print("❌ Failed to fetch username: \(error)")
        }
        
        return nil
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
            
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
            
            // Filter out archived goals
            // Note: GraphQL doesn't return archived field, so we check end date
            let now = Date()
            let calendar = Calendar(identifier: .gregorian)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            goals = goals.filter { goal in
                // If archived field is explicitly set, use it
                if goal.archived {
                    return false
                }
                
                // Otherwise, check end date (for GraphQL data that doesn't include archived field)
                guard let endDate = dateFormatter.date(from: goal.endDate) else {
                    return true // Keep if we can't parse the date
                }
                
                let daysSinceEnd = calendar.dateComponents([.day], from: endDate, to: now).day ?? 0
                return daysSinceEnd <= 30
            }
            
            print("🎯 Active goals after filtering archived: \(goals.count)")
            
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
            
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
            
            // Filter out archived goals
            // Note: GraphQL doesn't return archived field, so we check end date
            let now = Date()
            let calendar = Calendar(identifier: .gregorian)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            goals = goals.filter { goal in
                // If archived field is explicitly set, use it
                if goal.archived {
                    return false
                }
                
                // Otherwise, check end date (for GraphQL data that doesn't include archived field)
                guard let endDate = dateFormatter.date(from: goal.endDate) else {
                    return true // Keep if we can't parse the date
                }
                
                let daysSinceEnd = calendar.dateComponents([.day], from: endDate, to: now).day ?? 0
                return daysSinceEnd <= 30
            }
            
            print("🎯 Active goals after filtering archived: \(goals.count)")
            
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
    
    // MARK: - Fetch Reading Goals for Other Users
    /// Fetch reading goals for a specific user by scraping their goals page
    static func fetchUserReadingGoals(username: String) async -> [ReadingGoal] {
        do {
            guard !HardcoverConfig.apiKey.isEmpty else { throw HardcoverNetworkError.signIn }
            let cleanUsername = username.hasPrefix("@") ? String(username.dropFirst()) : username
            guard let escaped = cleanUsername.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://hardcover.app/@\(escaped)/goals") else {
                throw HardcoverNetworkError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
            try Task.checkCancellation()
            guard let html = String(data: data, encoding: .utf8),
                  let goals = extractGoalsFromHTML(html) else { throw HardcoverNetworkError.invalidResponse }
            return goals.filter { !$0.archived }
        } catch {
            HardcoverReadScope.failure?.record(error)
            return []
        }
    }

    static func extractGoalsFromHTML(_ html: String) -> [ReadingGoal]? {
        HardcoverGoalPage.decode(html)
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
                cached_contributors
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
                if let contributions = bookDict?["cached_contributors"] as? [[String: Any]],
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
        
        print("📚 finishBook called for userBookId: \(userBookId)")
        let today = utcDateString()
        
        // Fetch existing user_date to preserve it
        let existingUserDate = await fetchUserBookDate(userBookId: userBookId)
        print("📅 Existing user_date: \(existingUserDate ?? "nil")")
        
        var statusOK = true
        if let value = rating {
            let clamped = max(0.5, min(5.0, (round(value * 2) / 2)))
            statusOK = await updateUserBook(userBookId: userBookId, statusId: 3, rating: clamped, userDate: existingUserDate)
        } else {
            statusOK = await updateUserBookStatus(userBookId: userBookId, statusId: 3, userDate: existingUserDate)
        }
        print("✅ Status updated: \(statusOK)")
        if !statusOK { return false }
        
        // Try to update existing read first
        if let latestRead = await fetchLatestReadId(userBookId: userBookId) {
            print("📖 Found existing read ID: \(latestRead.id), updating finished_at")
            let updated = await updateReadFinishedAt(readId: latestRead.id, finishedAt: today)
            if updated {
                print("✅ Successfully updated existing read")
                return true
            }
            print("⚠️ Failed to update existing read")
        } else {
            print("⚠️ No ongoing read found")
            
            // If there's no user_date (start date), we still want to set a finish date
            // Create a read with finished_at but no started_at
            if existingUserDate == nil {
                print("📝 No start date exists, creating read with only finish date")
                let pages: Int? = totalPages ?? currentPage
                let created = await insertFinishedRead(userBookId: userBookId, editionId: editionId, pages: pages, finishedAt: today)
                print("✅ Created read with finish date: \(created)")
                return created
            }
            
            // If there is a user_date, Hardcover API will handle the read automatically
            print("✅ Status updated to finished, relying on Hardcover API to manage reads")
            return true
        }
        
        return false
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
    
    static func updateUserBook(userBookId: Int, statusId: Int, rating: Double?, userDate: String? = nil) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        var object: [String: Any] = ["status_id": statusId]
        if let r = rating { object["rating"] = r }
        if let date = userDate { object["user_date"] = date }
        
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
        
        // First, fetch the existing read to preserve started_at
        print("📖 Fetching existing read data to preserve started_at...")
        let fetchQuery = """
        query ($id: Int!) {
          user_book_reads(where: { id: { _eq: $id } }) {
            id
            started_at
            finished_at
          }
        }
        """
        let fetchBody: [String: Any] = [
            "query": fetchQuery,
            "variables": ["id": readId]
        ]
        
        var existingStartedAt: String? = nil
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: fetchBody)
            let (fetchData, _) = try await HardcoverHTTP.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: fetchData) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let reads = dataDict["user_book_reads"] as? [[String: Any]],
               let firstRead = reads.first,
               let startedAt = firstRead["started_at"] as? String {
                existingStartedAt = startedAt
                print("✅ Found existing started_at: \(startedAt)")
            } else {
                print("⚠️ No existing started_at found")
            }
        } catch {
            print("⚠️ Failed to fetch existing read: \(error)")
        }
        
        // Now update with preserved started_at and new finished_at
        var updateObject: [String: Any] = ["finished_at": finishedAt]
        if let startedAt = existingStartedAt {
            updateObject["started_at"] = startedAt
        }
        
        print("📝 Updating with object: \(updateObject)")
        
        let mutation = """
        mutation ($id: Int!, $started: date, $finished: date!) {
          update_user_book_read(id: $id, object: { started_at: $started, finished_at: $finished }) {
            error
            user_book_read { id started_at finished_at }
          }
        }
        """
        
        var variables: [String: Any] = ["id": readId, "finished": finishedAt]
        if let startedAt = existingStartedAt {
            variables["started"] = startedAt
        }
        
        let body: [String: Any] = [
            "query": mutation,
            "variables": variables
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                    print("❌ Update errors: \(errs)")
                    return false
                }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["update_user_book_read"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty { return false }
                    if let updatedRead = update["user_book_read"] as? [String: Any] {
                        print("✅ Updated read: \(updatedRead)")
                    }
                    return update["user_book_read"] != nil
                }
            }
        } catch {
            print("❌ Update error: \(error)")
            return false
        }
        return false
    }
    
    private static func updateReadDates(readId: Int, startedAt: String, finishedAt: String) async -> Bool {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "query": """
            mutation ($id: Int!, $started: date, $finished: date) {
              update_user_book_read(id: $id, object: { started_at: $started, finished_at: $finished }) {
                error
                user_book_read { id started_at finished_at }
              }
            }
            """,
            "variables": ["id": readId, "started": startedAt, "finished": finishedAt]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
    struct UpcomingRelease: Identifiable, Sendable {
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
              cached_contributors
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
            let resp = try JSONDecoder().decode(GraphQLUserBooksResponse.self, from: data)
            if let errs = resp.errors, !errs.isEmpty {
                HardcoverReadScope.failure?.record(HardcoverNetworkError.graphQL(errs.map(\.message).joined(separator: "\n")))
                return []
            }
            guard let rows = resp.data?.user_books else { HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse); return [] }
            
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
            HardcoverReadScope.failure?.record(error)
            return []
        }
    }
}

// MARK: - Recent Releases (Nyligen släppta böcker från Want to Read)
extension HardcoverService {
    static func fetchRecentReleasesFromWantToRead(limit: Int = 10) async -> [HardcoverService.UpcomingRelease] {
        guard !HardcoverConfig.apiKey.isEmpty else { HardcoverReadScope.failure?.record(HardcoverNetworkError.signIn); return [] }
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse); return [] }
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
              cached_contributors
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
        
        func parseDate(_ s: String) -> Date? { ReleaseDate.parse(s) }
        
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            let (data, response) = try await HardcoverHTTP.shared.data(for: request)
            
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
                if let contributions = bookDict["cached_contributors"] as? [[String: Any]],
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
            cached_contributors
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
                if let contribs = first["cached_contributors"] as? [[String: Any]],
                   let firstC = contribs.first,
                   let a = (firstC["author"] as? [String: Any])?["name"] as? String,
                   !a.isEmpty {
                    return a
                }
                return "Unknown Author"
            }()
            let desc = first["description"] as? String
            let coverURL = (first["image"] as? [String: Any])?["url"] as? String
            
            return BookProgress(
                id: "book-\(bookId)",
                title: title,
                author: author,
                coverImageUrl: coverURL,
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
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())
        
        var object: [String: Any] = [
            "book_id": bookId,
            "status_id": 3,
            "privacy_setting_id": privacySetting,
            "user_date": todayString
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
                    if let userBook = insert["user_book"] as? [String: Any],
                       let userBookId = userBook["id"] as? Int {
                        print("👤 Created user_book with ID: \(userBookId)")
                        
                        // Hardcover API creates a user_book_read automatically, but it might take a moment
                        // We only need to set finished_at, never change started_at
                        print("📝 Setting finished_at...")
                        
                        // Wait a bit for Hardcover API to create the read, then retry a few times
                        var readId: Int? = nil
                        for attempt in 1...3 {
                            if attempt > 1 {
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            }
                            readId = await fetchAnyReadId(userBookId: userBookId)
                            if readId != nil {
                                break
                            }
                            print("⏳ Attempt \(attempt): No read found yet, will retry...")
                        }
                        
                        if let readId = readId {
                            print("📖 Found read ID: \(readId), updating with finished_at only")
                            let updated = await updateReadFinishedAt(readId: readId, finishedAt: todayString)
                            print("✅ Updated read: \(updated)")
                        } else {
                            // If still no read exists after retries, create one with only finished_at
                            print("📝 No read found after retries, creating new one with only finished_at")
                            let created = await insertFinishedRead(userBookId: userBookId, editionId: editionId, pages: pages, finishedAt: todayString)
                            print("✅ Created read: \(created)")
                        }
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
        
        // Get current date in YYYY-MM-DD format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())

        var object: [String: Any] = [
            "book_id":  bookId,
            "status_id": 1,
            "privacy_setting_id": privacySetting,
            "user_date": todayString
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
            let (data, response) = try await HardcoverHTTP.shared.data(for: request)
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
            
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
        guard !HardcoverConfig.apiKey.isEmpty else { HardcoverReadScope.failure?.record(HardcoverNetworkError.signIn); return [] }
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            HardcoverReadScope.failure?.record(error)
            return []
        }
        HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
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
            
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
                let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
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
    
    // MARK: - Reading Journal Quotes
    
    struct ReadingJournalQuote: Codable, Sendable {
        let id: Int
        let entry: String
        let bookId: Int
        let createdAt: String
        let book: QuoteBook
        
        enum CodingKeys: String, CodingKey {
            case id
            case entry
            case bookId = "book_id"
            case createdAt = "created_at"
            case book
        }
        
        struct QuoteBook: Codable, Sendable {
            let title: String
            let contributions: [Contribution]
            
            struct Contribution: Codable, Sendable {
                let author: Author?
                
                struct Author: Codable, Sendable {
                    let name: String
                }
            }
        }
    }
    
    // New structure for user_books approach (better variety)
    struct UserBookWithQuotes: Codable {
        let book: QuoteBook
        let readingJournals: [JournalEntry]
        
        enum CodingKeys: String, CodingKey {
            case book
            case readingJournals = "reading_journals"
        }
        
        struct QuoteBook: Codable {
            let id: Int?
            let title: String
            let contributions: [Contribution]
            
            struct Contribution: Codable {
                let author: Author?
                
                struct Author: Codable {
                    let name: String
                }
            }
        }
        
        struct JournalEntry: Codable {
            let id: Int?
            let entry: String
            let event: String
            let objectType: String?
            let bookId: Int?
            
            enum CodingKeys: String, CodingKey {
                case id
                case entry
                case event
                case objectType = "object_type"
                case bookId = "book_id"
            }
        }
    }
    
    static func fetchReadingJournalQuotes() async -> [ReadingJournalQuote] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ fetchReadingJournalQuotes: No API key available")
            return []
        }
        
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else {
            print("❌ fetchReadingJournalQuotes: No user ID available")
            return []
        }
        
        // Use user_books approach to get ALL books with quotes (not chronologically limited)
        let query = """
        query {
          user_books(
            where: {
              user_id: {_eq: \(userId)},
              reading_journals: {event: {_eq: "quote"}}
            }
          ) {
            book {
              id
              title
              contributions {
                author {
                  name
                }
              }
            }
            reading_journals(where: {event: {_eq: "quote"}}) {
              id
              entry
              event
              object_type
              book_id
            }
          }
        }
        """
        
        let payload: [String: Any] = ["query": query]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("❌ Could not serialize query")
            return []
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid URL")
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await HardcoverHTTP.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("[Quotes] HTTP status: \(httpResponse.statusCode)")
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("❌ HTTP error: \(httpResponse.statusCode)")
                    return []
                }
            }
            
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[Quotes] Full response: \(jsonString)")
            }
            
            struct Response: Codable {
                let data: DataContainer
                
                struct DataContainer: Codable {
                    let userBooks: [UserBookWithQuotes]
                    
                    enum CodingKeys: String, CodingKey {
                        case userBooks = "user_books"
                    }
                }
            }
            
            let decoder = JSONDecoder()
            
            print("[Quotes] Attempting to decode response...")
            let decodedResponse = try decoder.decode(Response.self, from: data)
            let userBooks = decodedResponse.data.userBooks
            
            print("[Quotes] Successfully fetched \(userBooks.count) books with quotes")
            
            // Convert user_books with journals to flat list of ReadingJournalQuote
            // This maintains compatibility with existing widget code
            var allQuotes: [ReadingJournalQuote] = []
            for (index, userBook) in userBooks.enumerated() {
                let bookIdFromBook = userBook.book.id ?? 0
                for (journalIndex, journal) in userBook.readingJournals.enumerated() {
                    // Create a ReadingJournalQuote from the journal entry
                    let quote = ReadingJournalQuote(
                        id: journal.id ?? (index * 1000 + journalIndex), // Use real ID when available
                        entry: journal.entry,
                        bookId: journal.bookId ?? bookIdFromBook, // Use real book ID
                        createdAt: "", // Not needed for widget display
                        book: ReadingJournalQuote.QuoteBook(
                            title: userBook.book.title,
                            contributions: userBook.book.contributions.map { contrib in
                                ReadingJournalQuote.QuoteBook.Contribution(
                                    author: contrib.author.map { author in
                                        ReadingJournalQuote.QuoteBook.Contribution.Author(name: author.name)
                                    }
                                )
                            }
                        )
                    )
                    allQuotes.append(quote)
                }
            }
            
            print("[Quotes] Converted to \(allQuotes.count) total quotes from all books")
            if allQuotes.count > 0 {
                print("[Quotes] First quote preview: \(allQuotes[0].entry.prefix(50))...")
            }
            return allQuotes
            
        } catch {
            print("❌ Error fetching quotes: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("❌ Key '\(key.stringValue)' not found: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("❌ Type mismatch for type \(type): \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("❌ Value not found for type \(type): \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("❌ Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("❌ Unknown decoding error")
                }
            }
            return []
        }
    }
}
