import Foundation

extension HardcoverService {
    // Public, nested review model used by BookDetailView and other detail views.
    struct PublicReview: Identifiable {
        let id: Int                   // likeableId (user_book id)
        let rating: Double?
        let reviewedAt: Date?
        let text: String?
        let username: String?
        // Likes
        let likesCount: Int
        let userHasLiked: Bool
    }
    
    // MARK: - Public Reviews for a Book (+ likes)
    static func fetchPublicReviewsForBook(bookId: Int, limit: Int = 20, offset: Int = 0) async -> [PublicReview] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Primärfråga: publika recensioner (privacy_setting_id = 1) med user.username
        let query = """
        query ($bookId: Int!, $limit: Int!, $offset: Int!) {
          user_books(
            where: {
              book_id: { _eq: $bookId }
              has_review: { _eq: true }
              privacy_setting_id: { _eq: 1 }
            },
            order_by: [{ reviewed_at: desc_nulls_last }, { id: desc }],
            limit: $limit,
            offset: $offset
          ) {
            id
            rating
            reviewed_at
            review_raw
            user_id
            user { id username }
          }
        }
        """
        let vars: [String: Any] = ["bookId": bookId, "limit": limit, "offset": offset]
        let body: [String: Any] = ["query": query, "variables": vars]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                // Fallback till enklare variant utan user
                return await fetchPublicReviewsForBook_FallbackNoUser(bookId: bookId, limit: limit, offset: offset)
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = root["data"] as? [String: Any],
                  let rows = dataDict["user_books"] as? [[String: Any]] else {
                return []
            }
            // Grunddata
            var base: [(id: Int, rating: Double?, reviewedAt: Date?, text: String?, username: String?)] = []
            base.reserveCapacity(rows.count)
            for row in rows {
                let id = (row["id"] as? Int) ?? -1
                let rating = row["rating"] as? Double
                let reviewedAtStr = row["reviewed_at"] as? String
                let reviewedAt = parseAPITimestamp(reviewedAtStr ?? "")
                let text = row["review_raw"] as? String
                var username: String? = nil
                if let user = row["user"] as? [String: Any],
                   let u = user["username"] as? String, !u.isEmpty {
                    username = u
                }
                base.append((id, rating, reviewedAt, text, username))
            }
            // Likes-berikning
            let ids = base.map { $0.id }
            let likeInfo = await fetchLikesBatch(for: ids)
            // Slå ihop
            return base.map { item in
                let (count, mine) = likeInfo[item.id] ?? (0, false)
                return PublicReview(
                    id: item.id,
                    rating: item.rating,
                    reviewedAt: item.reviewedAt,
                    text: item.text,
                    username: item.username,
                    likesCount: count,
                    userHasLiked: mine
                )
            }
        } catch {
            // Fallback
            return await fetchPublicReviewsForBook_FallbackNoUser(bookId: bookId, limit: limit, offset: offset)
        }
    }
    
    private static func fetchPublicReviewsForBook_FallbackNoUser(bookId: Int, limit: Int, offset: Int) async -> [PublicReview] {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($bookId: Int!, $limit: Int!, $offset: Int!) {
          user_books(
            where: {
              book_id: { _eq: $bookId }
              has_review: { _eq: true }
            },
            order_by: [{ reviewed_at: desc_nulls_last }, { id: desc }],
            limit: $limit,
            offset: $offset
          ) {
            id
            rating
            reviewed_at
            review_raw
          }
        }
        """
        let vars: [String: Any] = ["bookId": bookId, "limit": limit, "offset": offset]
        let body: [String: Any] = ["query": query, "variables": vars]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return []
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = root["data"] as? [String: Any],
                  let rows = dataDict["user_books"] as? [[String: Any]] else {
                return []
            }
            let ids = rows.compactMap { $0["id"] as? Int }
            let likeInfo = await fetchLikesBatch(for: ids)
            return rows.map { row in
                let id = (row["id"] as? Int) ?? -1
                let rating = row["rating"] as? Double
                let reviewedAtStr = row["reviewed_at"] as? String
                let reviewedAt = parseAPITimestamp(reviewedAtStr ?? "")
                let text = row["review_raw"] as? String
                let (count, mine) = likeInfo[id] ?? (0, false)
                return PublicReview(
                    id: id,
                    rating: rating,
                    reviewedAt: reviewedAt,
                    text: text,
                    username: nil,
                    likesCount: count,
                    userHasLiked: mine
                )
            }
        } catch {
            return []
        }
    }
    
    // Batched likes fetch for many likeableIds
    private static func fetchLikesBatch(for likeableIds: [Int]) async -> [Int: (count: Int, mine: Bool)] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [:] }
        guard !likeableIds.isEmpty else { return [:] }
        // Use a local helper to avoid depending on a private function declared elsewhere.
        guard let userId = await fetchUserIdForReviews(apiKey: HardcoverConfig.apiKey) else { return [:] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [:] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($ids: [Int!], $type: String!, $userId: Int!) {
          likes(where: { likeable_id: { _in: $ids }, likeable_type: { _eq: $type } }) {
            likeable_id
          }
          myLikes: likes(where: { likeable_id: { _in: $ids }, likeable_type: { _eq: $type }, user_id: { _eq: $userId } }) {
            likeable_id
          }
        }
        """
        let vars: [String: Any] = ["ids": likeableIds, "type": "UserBook", "userId": userId]
        let body: [String: Any] = ["query": query, "variables": vars]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["errors"] as? [[String: Any]])?.isEmpty != false,
                  let dataDict = root["data"] as? [String: Any] else {
                return [:]
            }
            let likes = (dataDict["likes"] as? [[String: Any]] ?? []).compactMap { $0["likeable_id"] as? Int }
            let my = Set((dataDict["myLikes"] as? [[String: Any]] ?? []).compactMap { $0["likeable_id"] as? Int })
            
            var counts: [Int: Int] = [:]
            for id in likes { counts[id, default: 0] += 1 }
            var result: [Int: (count: Int, mine: Bool)] = [:]
            for id in likeableIds {
                result[id] = (counts[id] ?? 0, my.contains(id))
            }
            return result
        } catch {
            return [:]
        }
    }
    
    // Local helper: fetch current user id using the API key
    private static func fetchUserIdForReviews(apiKey: String) async -> Int? {
        guard !apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let body = "{ \"query\": \"{ me { id username } }\" }"
        req.httpBody = body.data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any] {
                // Some schemas return an array for `me`, others a single object. Support both.
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
        } catch {
            return nil
        }
        return nil
    }
    
    // Robust timestamp parser (ISO8601 with/without fractional seconds; fallback yyyy-MM-dd)
    private static func parseAPITimestamp(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: s) { return d }
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }
    
    /// Publish a public review for a given user_book.
    /// Adjust mutation/fields to match your GraphQL schema if needed.
    static func publishReview(userBookId: Int, text: String, hasSpoilers: Bool) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else { return false }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Convert plain text into a minimal Slate JSON document
        // Split on newlines -> one paragraph per line
        let paragraphs = text
            .split(whereSeparator: { $0.isNewline })
            .map { String($0) }
            .map { line in
                [
                    "data": [:] as [String: Any],
                    "object": "block",
                    "type": "paragraph",
                    "children": [[
                        "object": "text",
                        "text": line
                    ]]
                ] as [String: Any]
            }
        // If text was empty or only newlines (should be filtered by caller), ensure at least one empty paragraph
        let slate: [Any] = paragraphs.isEmpty ? [[
            "data": [:] as [String: Any],
            "object": "block",
            "type": "paragraph",
            "children": [[
                "object": "text",
                "text": ""
            ]]
        ] as [String: Any]] : paragraphs
        
        // reviewed_at as yyyy-MM-dd
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        let reviewedAt = df.string(from: Date())
        
        // Build update object
        var object: [String: Any] = [
            "review_has_spoilers": hasSpoilers,
            "private_notes": "",
            "review_slate": slate,
            "reviewed_at": reviewedAt,
            "url": NSNull(),
            "media_url": NSNull(),
            "sponsored_review": false
        ]
        
        let mutation = """
        mutation UpdateUserBook($id: Int!, $object: UserBookUpdateInput!) {
          updateResponse: update_user_book(id: $id, object: $object) {
            error
            userBook: user_book { id has_review reviewed_at }
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
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty { return false }
                if let dataDict = root["data"] as? [String: Any],
                   let update = dataDict["updateResponse"] as? [String: Any] {
                    if let err = update["error"] as? String, !err.isEmpty { return false }
                    return update["userBook"] != nil
                }
            }
            return false
        } catch {
            return false
        }
    }
}
