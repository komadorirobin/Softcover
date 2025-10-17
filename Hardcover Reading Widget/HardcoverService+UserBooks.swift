import Foundation

extension HardcoverService {
    /// Fetch user ID by username
    private static func fetchUserId(username: String) async -> Int? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        {
          users(where: {username: {_eq: "\(username)"}}, limit: 1) {
            id
          }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let users = dataDict["users"] as? [[String: Any]],
               let user = users.first,
               let userId = user["id"] as? Int {
                return userId
            }
        } catch {
            print("❌ Error fetching user ID: \(error)")
        }
        
        return nil
    }
    
    /// Fetch user's Want to Read books
    static func fetchUserWantToRead(username: String) async throws -> [BookProgress] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key available"])
        }
        
        guard let userId = await fetchUserId(username: username) else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        {
          user_books(where: {user_id: {_eq: \(userId)}, status_id: {_eq: 1}}, order_by: {id: desc}) {
            id
            book_id
            status_id
            edition_id
            rating
            book {
              id
              title
              contributions(limit: 1) {
                author {
                  name
                }
              }
              image {
                url
              }
            }
            edition {
              id
              title
              image {
                url
              }
            }
          }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body"])
        }
        
        req.httpBody = httpBody
        
        let (data, _) = try await URLSession.shared.data(for: req)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let userBooks = dataDict["user_books"] as? [[String: Any]] else {
            return []
        }
        
        return userBooks.compactMap { userBook -> BookProgress? in
            guard let book = userBook["book"] as? [String: Any],
                  let id = book["id"] as? Int,
                  let rawTitle = book["title"] as? String else {
                return nil
            }
            
            // Prefer edition title if available
            var title = rawTitle.decodedHTMLEntities
            if let edition = userBook["edition"] as? [String: Any],
               let editionTitle = edition["title"] as? String,
               !editionTitle.isEmpty {
                title = editionTitle.decodedHTMLEntities
            }
            
            // Prefer edition image if available
            var imageUrl: String? = nil
            if let edition = userBook["edition"] as? [String: Any],
               let editionImage = edition["image"] as? [String: Any],
               let url = editionImage["url"] as? String {
                imageUrl = url
            } else if let bookImage = book["image"] as? [String: Any],
                      let url = bookImage["url"] as? String {
                imageUrl = url
            }
            
            var author = "Unknown Author"
            if let contributions = book["contributions"] as? [[String: Any]],
               let firstContrib = contributions.first,
               let authorDict = firstContrib["author"] as? [String: Any],
               let authorName = authorDict["name"] as? String {
                author = authorName
            }
            
            return BookProgress(
                id: "\(id)",
                title: title,
                author: author,
                coverImageData: nil,
                coverImageUrl: imageUrl,
                progress: 0.0,
                totalPages: 0,
                currentPage: 0,
                bookId: id,
                userBookId: userBook["id"] as? Int,
                editionId: userBook["edition_id"] as? Int,
                originalTitle: rawTitle.decodedHTMLEntities
            )
        }
    }
    
    /// Fetch user's Currently Reading books
    static func fetchUserCurrentlyReading(username: String) async throws -> [BookProgress] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key available"])
        }
        
        guard let userId = await fetchUserId(username: username) else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        {
          user_books(where: {user_id: {_eq: \(userId)}, status_id: {_eq: 2}}, order_by: {id: desc}) {
            id
            book_id
            status_id
            edition_id
            rating
            user_book_reads(order_by: {id: asc}) {
              id
              started_at
              finished_at
              progress_pages
              edition_id
            }
            book {
              id
              title
              contributions(limit: 1) {
                author {
                  name
                }
              }
              image {
                url
              }
            }
            edition {
              id
              title
              pages
              image {
                url
              }
            }
          }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body"])
        }
        
        req.httpBody = httpBody
        
        let (data, _) = try await URLSession.shared.data(for: req)
        
        // Debug logging for Currently Reading
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📚 Currently Reading Response for \(username): \(jsonString.prefix(1000))")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let userBooks = dataDict["user_books"] as? [[String: Any]] else {
            print("❌ Failed to parse Currently Reading for \(username)")
            return []
        }
        
        print("✅ Currently Reading: Found \(userBooks.count) books for \(username)")
        
        return userBooks.compactMap { userBook -> BookProgress? in
            guard let book = userBook["book"] as? [String: Any],
                  let id = book["id"] as? Int,
                  let rawTitle = book["title"] as? String else {
                return nil
            }
            
            // Prefer edition title if available
            var title = rawTitle.decodedHTMLEntities
            if let edition = userBook["edition"] as? [String: Any],
               let editionTitle = edition["title"] as? String,
               !editionTitle.isEmpty {
                title = editionTitle.decodedHTMLEntities
            }
            
            // Prefer edition image if available
            var imageUrl: String? = nil
            if let edition = userBook["edition"] as? [String: Any],
               let editionImage = edition["image"] as? [String: Any],
               let url = editionImage["url"] as? String {
                imageUrl = url
            } else if let bookImage = book["image"] as? [String: Any],
                      let url = bookImage["url"] as? String {
                imageUrl = url
            }
            
            // Get progress from latest user_book_read
            var progress = 0
            if let userBookReads = userBook["user_book_reads"] as? [[String: Any]],
               let latestRead = userBookReads.last,
               let progressPages = latestRead["progress_pages"] as? Int {
                progress = progressPages
            }
            
            var totalPages = 0
            if let edition = userBook["edition"] as? [String: Any],
               let pages = edition["pages"] as? Int {
                totalPages = pages
            }
            
            var author = "Unknown Author"
            if let contributions = book["contributions"] as? [[String: Any]],
               let firstContrib = contributions.first,
               let authorDict = firstContrib["author"] as? [String: Any],
               let authorName = authorDict["name"] as? String {
                author = authorName
            }
            
            return BookProgress(
                id: "\(id)",
                title: title,
                author: author,
                coverImageData: nil,
                coverImageUrl: imageUrl,
                progress: totalPages > 0 ? Double(progress) / Double(totalPages) : 0.0,
                totalPages: totalPages,
                currentPage: progress,
                bookId: id,
                userBookId: userBook["id"] as? Int,
                editionId: userBook["edition_id"] as? Int,
                originalTitle: rawTitle.decodedHTMLEntities
            )
        }
    }
    
    /// Fetch user's Finished books
    static func fetchUserFinished(username: String) async throws -> [FinishedBookEntry] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key available"])
        }
        
        guard let userId = await fetchUserId(username: username) else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        {
          user_book_reads(
            where: {
              finished_at: {_is_null: false},
              user_book: {user_id: {_eq: \(userId)}, status_id: {_eq: 3}}
            },
            order_by: [{finished_at: desc}, {id: desc}],
            limit: 100
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
                contributions(limit: 1) {
                  author {
                    name
                  }
                }
                image {
                  url
                }
              }
              edition {
                id
                title
                image {
                  url
                }
              }
            }
          }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw NSError(domain: "HardcoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body"])
        }
        
        req.httpBody = httpBody
        
        let (data, _) = try await URLSession.shared.data(for: req)
        
        // Debug logging for Finished
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📚 Finished Books Response for \(username): \(jsonString.prefix(1000))")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let reads = dataDict["user_book_reads"] as? [[String: Any]] else {
            print("❌ Failed to parse Finished Books for \(username)")
            return []
        }
        
        print("✅ Finished: Found \(reads.count) books for \(username)")
        
        return reads.compactMap { read -> FinishedBookEntry? in
            guard let readId = read["id"] as? Int,
                  let finishedAtString = read["finished_at"] as? String,
                  let userBook = read["user_book"] as? [String: Any],
                  let bookId = userBook["book_id"] as? Int,
                  let book = userBook["book"] as? [String: Any],
                  let rawTitle = book["title"] as? String else {
                return nil
            }
            
            let userBookId = userBook["id"] as? Int
            
            // Prefer edition title if available
            var title = rawTitle.decodedHTMLEntities
            if let edition = userBook["edition"] as? [String: Any],
               let editionTitle = edition["title"] as? String,
               !editionTitle.isEmpty {
                title = editionTitle.decodedHTMLEntities
            }
            
            // Prefer edition image if available
            var imageUrl: String? = nil
            if let edition = userBook["edition"] as? [String: Any],
               let editionImage = edition["image"] as? [String: Any],
               let url = editionImage["url"] as? String {
                imageUrl = url
            } else if let bookImage = book["image"] as? [String: Any],
                      let url = bookImage["url"] as? String {
                imageUrl = url
            }
            
            let rating = userBook["rating"] as? Double
            
            var author = "Unknown Author"
            if let contributions = book["contributions"] as? [[String: Any]],
               let firstContrib = contributions.first,
               let authorDict = firstContrib["author"] as? [String: Any],
               let authorName = authorDict["name"] as? String {
                author = authorName
            }
            
            // Parse the finished_at date (format: "yyyy-MM-dd" or ISO8601)
            func parseDate(_ s: String) -> Date? {
                // Try ISO8601 first
                let iso8601 = ISO8601DateFormatter()
                if let d = iso8601.date(from: s) { return d }
                
                // Try simple date format "yyyy-MM-dd"
                let df = DateFormatter()
                df.calendar = Calendar(identifier: .gregorian)
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "yyyy-MM-dd"
                if let d = df.date(from: s) { return d }
                
                return nil
            }
            
            guard let finishedAt = parseDate(finishedAtString) else {
                return nil
            }
            
            return FinishedBookEntry(
                id: readId,
                bookId: bookId,
                userBookId: userBookId,
                title: title,
                author: author,
                rating: rating,
                finishedAt: finishedAt,
                coverImageData: nil,
                coverImageUrl: imageUrl
            )
        }
    }
}
