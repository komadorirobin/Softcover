import Foundation

extension HardcoverService {
    // Start reading by book/edition (status_id = 2).
    // If a user_book for this book already exists for the current user, update it.
    // Otherwise, create a new user_book entry.
    static func startReadingBook(bookId: Int, editionId: Int?) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ startReadingBook: API key is empty")
            return false
        }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ startReadingBook: Invalid URL")
            return false
        }
        
        // 1) Resolve current user id
        print("🔍 Fetching current user ID...")
        guard let userId = await fetchCurrentUserId(apiURL: url) else {
            print("❌ startReadingBook: Could not fetch current user ID")
            return false
        }
        print("✅ Got user ID: \(userId)")
        
        // 2) Try to find an existing user_book for this user and book
        print("🔍 Checking for existing user_book...")
        if let existingId = await fetchExistingUserBookId(apiURL: url, userId: userId, bookId: bookId) {
            print("📖 Found existing user_book with ID: \(existingId), updating to reading status...")
            // Update to status 2 (reading) and optionally set edition
            return await updateUserBookToReading(apiURL: url, userBookId: existingId, editionId: editionId)
        } else {
            print("📖 No existing user_book found, creating new entry...")
            // 3) Insert a new user_book with status 2 (reading)
            return await insertUserBookAsReading(apiURL: url, userId: userId, bookId: bookId, editionId: editionId)
        }
    }
    
    // MARK: - Helpers
    
    private static func fetchCurrentUserId(apiURL: URL) async -> Int? {
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let body = "{ \"query\": \"{ me { id username } }\" }"
        req.httpBody = body.data(using: .utf8)
        do {
            let (data, _) = try await HardcoverHTTP.shared.data(for: req)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any] {
                if let meArr = dataDict["me"] as? [[String: Any]],
                   let first = meArr.first,
                   let id = first["id"] as? Int {
                    return id
                }
                if let meObj = dataDict["me"] as? [String: Any],
                   let id = meObj["id"] as? Int {
                    return id
                }
            }
        } catch { return nil }
        return nil
    }
    
    private static func fetchExistingUserBookId(apiURL: URL, userId: Int, bookId: Int) async -> Int? {
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($userId: Int!, $bookId: Int!) {
          user_books(
            where: { user_id: { _eq: $userId }, book_id: { _eq: $bookId } },
            order_by: [{ id: desc }],
            limit: 1
          ) { id }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId, "bookId": bookId]
        ]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await HardcoverHTTP.shared.data(for: req)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first,
               let id = first["id"] as? Int {
                return id
            }
        } catch { return nil }
        return nil
    }
    
    private static func updateUserBookToReading(apiURL: URL, userBookId: Int, editionId: Int?) async -> Bool {
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        var object: [String: Any] = ["status_id": 2]
        if let eid = editionId { object["edition_id"] = eid }
        let mutation = """
        mutation UpdateUserBook($id: Int!, $object: UserBookUpdateInput!) {
          update_user_book(id: $id, object: $object) {
            error
            user_book { id status_id }
          }
        }
        """
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["id": userBookId, "object": object]
        ]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await HardcoverHTTP.shared.data(for: req)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty { return false }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["update_user_book"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty { return false }
                    return update["user_book"] != nil
                }
            }
        } catch { return false }
        return false
    }
    
    private static func insertUserBookAsReading(apiURL: URL, userId: Int, bookId: Int, editionId: Int?) async -> Bool {
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Get current date in YYYY-MM-DD format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())
        
        // Get privacy setting
        let privacySettingId = await fetchAccountPrivacySettingId() ?? 1
        
        var object: [String: Any] = [
            "book_id": bookId,
            "status_id": 2,
            "privacy_setting_id": privacySettingId,
            "user_date": todayString
        ]
        if let eid = editionId { object["edition_id"] = eid }
        
        let mutation = """
        mutation InsertUserBook($object: UserBookCreateInput!) {
          insert_user_book(object: $object) {
            error
            user_book { id }
          }
        }
        """
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["object": object]
        ]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await HardcoverHTTP.shared.data(for: req)
            
            // Log the response
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 insertUserBookAsReading response: \(responseString)")
            }
            
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
                    print("❌ insertUserBookAsReading GraphQL errors: \(errors)")
                    return false
                }
                if let dataDict = root["data"] as? [String: Any],
                   let insert = dataDict["insert_user_book"] as? [String: Any] {
                    if let err = insert["error"] as? String, !err.isEmpty {
                        print("❌ insertUserBookAsReading error: \(err)")
                        return false
                    }
                    if insert["user_book"] != nil {
                        print("✅ Successfully inserted user_book for reading")
                        return true
                    }
                }
            }
        } catch {
            print("❌ insertUserBookAsReading exception: \(error)")
            return false
        }
        print("❌ insertUserBookAsReading: Unknown failure")
        return false
    }
}
