import Foundation

// MARK: - Feed Models

struct FeedActivity: Identifiable {
    let id: Int
    let event: String
    let createdAt: String
    let userId: Int?
    
    // User info
    let username: String
    let userImageURL: String?
    let userFlair: String?
    
    // Book info (if applicable)
    let bookId: Int?
    let bookTitle: String?
    let bookImageURL: String?
    let authorName: String?
    
    // Extra data
    let rating: Double?
    let reviewText: String?
    let progress: Int?         // percentage 0-100
    let statusId: Int?         // 1=want, 2=reading, 3=read, 5=dnf
    
    /// Human-readable action text
    var actionText: String {
        switch event {
        case "UserBookActivity":
            switch statusId {
            case 1:  return "wants to read"
            case 2:  return "is currently reading"
            case 3:  return "finished reading"
            case 5:  return "stopped reading"
            default: return "updated"
            }
        case "StatusUpdate":
            switch statusId {
            case 1:  return "wants to read"
            case 2:  return "is currently reading"
            case 3:  return "finished reading"
            case 5:  return "stopped reading"
            default: return "updated status for"
            }
        case "ReviewActivity":
            return "reviewed"
        case "GoalActivity":
            return "updated a reading goal"
        case "ListActivity":
            if let listName = reviewText, !listName.isEmpty {
                return "added to \(listName)"
            }
            return "updated a list"
        default:
            return event
                .replacingOccurrences(of: "Activity", with: "")
                .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
                .lowercased()
        }
    }
    
    var actionIcon: String {
        switch event {
        case "UserBookActivity":
            switch statusId {
            case 1:  return "bookmark.fill"
            case 2:  return "book.fill"
            case 3:  return "checkmark.circle.fill"
            case 5:  return "xmark.circle.fill"
            default: return "arrow.triangle.2.circlepath"
            }
        case "StatusUpdate":
            switch statusId {
            case 1:  return "bookmark.fill"
            case 2:  return "book.fill"
            case 3:  return "checkmark.circle.fill"
            case 5:  return "xmark.circle.fill"
            default: return "arrow.triangle.2.circlepath"
            }
        case "ReviewActivity":
            return "star.bubble.fill"
        case "GoalActivity":
            return "target"
        case "ListActivity":
            return "list.bullet"
        default:
            return "bell.fill"
        }
    }
    
    var actionColor: String {
        switch event {
        case "UserBookActivity":
            switch statusId {
            case 1:  return "blue"
            case 2:  return "green"
            case 3:  return "orange"
            case 5:  return "red"
            default: return "gray"
            }
        case "StatusUpdate":
            switch statusId {
            case 1:  return "blue"
            case 2:  return "green"
            case 3:  return "orange"
            case 5:  return "red"
            default: return "gray"
            }
        case "ReviewActivity":
            return "yellow"
        default:
            return "purple"
        }
    }
}

// MARK: - GraphQL Responses for Feed
// (Using manual JSONSerialization parsing for flexibility)

extension HardcoverService {
    
    // MARK: - Fetch Feed (Following)
    
    /// Fetch feed activities from users the current user follows.
    /// Uses the `activities` table filtering by followed user IDs.
    static func fetchFeed(offset: Int = 0, limit: Int = 20) async -> [FeedActivity] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ [Feed] No API key available")
            return []
        }
        
        // First get the IDs of users we follow
        let following = await fetchFollowing()
        let followingIds = following.map { $0.id }
        
        guard !followingIds.isEmpty else {
            print("⚠️ [Feed] Not following anyone — feed is empty")
            return []
        }
        
        // Also get own user ID to include own activity
        let myId = await fetchCurrentUserId()
        var allIds = followingIds
        if let myId = myId {
            allIds.append(myId)
        }
        
        return await fetchActivities(forUserIds: allIds, offset: offset, limit: limit)
    }
    
    // MARK: - Fetch All Activity (global)
    
    /// Fetch all recent public activities (not filtered by following).
    static func fetchAllActivity(offset: Int = 0, limit: Int = 20) async -> [FeedActivity] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ [Feed] No API key available")
            return []
        }
        
        return await fetchActivities(forUserIds: nil, offset: offset, limit: limit)
    }
    
    /// Fetch activities optionally filtered by user IDs.
    /// First tries GraphQL, falls back to scraping the feed page.
    private static func fetchActivities(forUserIds userIds: [Int]?, offset: Int, limit: Int) async -> [FeedActivity] {
        if userIds != nil {
            // "Your Feed" — always use GraphQL with user ID filtering
            // (HTML /feed page doesn't authenticate via Bearer token)
            return await fetchActivitiesViaGraphQL(forUserIds: userIds, offset: offset, limit: limit)
        } else {
            // "All Activity" — try HTML first for richer data, then GraphQL
            let feedActivities = await fetchFeedFromHTML(path: "/feed/all", offset: offset, limit: limit)
            if !feedActivities.isEmpty { return feedActivities }
            return await fetchActivitiesViaGraphQL(forUserIds: nil, offset: offset, limit: limit)
        }
    }
    
    // MARK: - Feed from HTML (Inertia.js)
    
    /// Fetch feed by scraping the Hardcover website's Inertia.js data.
    private static func fetchFeedFromHTML(path: String, offset: Int, limit: Int) async -> [FeedActivity] {
        // For pagination: page parameter (Inertia uses page-based)
        let page = (offset / max(limit, 1)) + 1
        let urlString = page > 1
            ? "https://hardcover.app\(path)?page=\(page)"
            : "https://hardcover.app\(path)"
        
        guard let url = URL(string: urlString) else {
            print("❌ [Feed] Invalid URL: \(urlString)")
            return []
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 [Feed] HTML response status: \(httpResponse.statusCode)")
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ [Feed] Could not decode HTML")
                return []
            }
            
            // Debug: log a snippet to understand the page structure
            if html.contains("data-page") {
                print("✅ [Feed] Found data-page attribute in HTML")
            } else {
                print("⚠️ [Feed] No data-page attribute found. HTML length: \(html.count)")
                print("📦 [Feed] HTML snippet: \(String(html.prefix(500)))")
            }
            
            return parseFeedHTML(html)
        } catch {
            print("❌ [Feed] Failed to fetch feed HTML: \(error)")
            return []
        }
    }
    
    /// Parse feed data from Inertia props JSON
    private static func parseFeedProps(_ props: [String: Any]) -> [FeedActivity] {
        // The feed page passes activities/statuses in props
        // Common keys: "activities", "statuses", "data", "feed"
        let activitiesArray: [[String: Any]]?
        
        if let activities = props["activities"] as? [[String: Any]] {
            activitiesArray = activities
        } else if let statuses = props["statuses"] as? [[String: Any]] {
            activitiesArray = statuses
        } else if let feed = props["feed"] as? [[String: Any]] {
            activitiesArray = feed
        } else if let dataObj = props["data"] as? [[String: Any]] {
            activitiesArray = dataObj
        } else {
            // Try to find any array in props that looks like feed items
            print("⚠️ [Feed] Available props keys: \(props.keys.sorted())")
            activitiesArray = nil
        }
        
        guard let items = activitiesArray else {
            print("⚠️ [Feed] Could not find activities in Inertia props")
            return []
        }
        
        print("✅ [Feed] Parsed \(items.count) activities from Inertia props")
        return items.enumerated().compactMap { index, item in
            parseFeedItem(item, fallbackId: index)
        }
    }
    
    /// Parse feed data from HTML data-page attribute
    private static func parseFeedHTML(_ html: String) -> [FeedActivity] {
        guard let dataPageRange = html.range(of: "data-page=\"") else {
            print("❌ [Feed] Could not find data-page attribute")
            return []
        }
        
        let startIndex = dataPageRange.upperBound
        guard let endIndex = html[startIndex...].range(of: "\">")?.lowerBound
                ?? html[startIndex...].range(of: "\"")?.lowerBound else {
            print("❌ [Feed] Could not find end of data-page")
            return []
        }
        
        let jsonString = String(html[startIndex..<endIndex])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        
        guard let jsonData = jsonString.data(using: .utf8),
              let pageData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let props = pageData["props"] as? [String: Any] else {
            print("❌ [Feed] Failed to parse data-page JSON")
            return []
        }
        
        return parseFeedProps(props)
    }
    
    /// Parse a single feed item from Inertia data
    private static func parseFeedItem(_ item: [String: Any], fallbackId: Int) -> FeedActivity? {
        let id = item["id"] as? Int ?? fallbackId
        
        // Determine event type from Inertia data
        let action = item["action"] as? String
            ?? item["event"] as? String
            ?? item["action_text"] as? String
            ?? ""
        
        let createdAt = item["created_at"] as? String
            ?? item["updated_at"] as? String
            ?? ""
        
        // User info
        let user = item["user"] as? [String: Any]
        let username = user?["username"] as? String
            ?? item["username"] as? String
            ?? "Unknown"
        let userImageURL = (user?["image"] as? [String: Any])?["url"] as? String
            ?? (user?["cached_image"] as? [String: Any])?["url"] as? String
            ?? user?["image_url"] as? String
        let userFlair = user?["flair"] as? String
        let userId = user?["id"] as? Int ?? item["user_id"] as? Int
        
        // Book info
        let book = item["book"] as? [String: Any]
            ?? (item["user_book"] as? [String: Any])?["book"] as? [String: Any]
        let bookId = book?["id"] as? Int
            ?? item["book_id"] as? Int
        let bookTitle = book?["title"] as? String
            ?? item["book_title"] as? String
        let bookImageURL = (book?["image"] as? [String: Any])?["url"] as? String
            ?? (book?["cached_image"] as? [String: Any])?["url"] as? String
        
        // Author
        var authorName: String?
        if let contributions = book?["contributions"] as? [[String: Any]] {
            authorName = contributions
                .compactMap { ($0["author"] as? [String: Any])?["name"] as? String }
                .joined(separator: ", ")
        }
        if authorName == nil || authorName?.isEmpty == true {
            authorName = item["author_name"] as? String
                ?? book?["author"] as? String
        }
        
        // Status/rating/review/progress
        let statusId = item["status_id"] as? Int
            ?? (item["user_book"] as? [String: Any])?["status_id"] as? Int
        let rating = item["rating"] as? Double
            ?? (item["rating"] as? Int).map { Double($0) }
        let reviewText = item["review"] as? String
            ?? item["review_text"] as? String
            ?? item["body"] as? String
        let progress = item["progress"] as? Int
            ?? item["percentage"] as? Int
        
        // Map action strings to event names
        let event = mapActionToEvent(action: action, statusId: statusId)
        
        return FeedActivity(
            id: id,
            event: event,
            createdAt: createdAt,
            userId: userId,
            username: username,
            userImageURL: userImageURL,
            userFlair: userFlair,
            bookId: bookId,
            bookTitle: bookTitle,
            bookImageURL: bookImageURL,
            authorName: authorName,
            rating: rating,
            reviewText: reviewText,
            progress: progress,
            statusId: statusId
        )
    }
    
    private static func mapActionToEvent(action: String, statusId: Int?) -> String {
        let lower = action.lowercased()
        if lower.contains("finished") || lower.contains("read") && !lower.contains("want") && !lower.contains("currently") {
            return "StatusUpdate"
        }
        if lower.contains("currently reading") || lower.contains("is reading") {
            return "StatusUpdate"
        }
        if lower.contains("want") {
            return "StatusUpdate"
        }
        if lower.contains("stopped") || lower.contains("dnf") || lower.contains("did not finish") {
            return "StatusUpdate"
        }
        if lower.contains("review") || lower.contains("rated") {
            return "ReviewActivity"
        }
        if lower.contains("progress") || lower.contains("% done") {
            return "StatusUpdate"
        }
        if statusId != nil {
            return "StatusUpdate"
        }
        if !action.isEmpty {
            return action
        }
        return "StatusUpdate"
    }
    
    // MARK: - GraphQL Fallback
    
    private static func fetchActivitiesViaGraphQL(forUserIds userIds: [Int]?, offset: Int, limit: Int) async -> [FeedActivity] {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ [Feed] Invalid API URL")
            return []
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Build where clause — don't filter by event type,
        // let all activity types through and filter client-side if needed
        let whereClause: String
        if let userIds = userIds {
            let idsString = userIds.map { String($0) }.joined(separator: ", ")
            whereClause = "where: {user_id: {_in: [\(idsString)]}}"
        } else {
            whereClause = ""
        }
        
        let whereFragment = whereClause.isEmpty ? "" : "\(whereClause),"
        let query = """
        {
            activities(
                \(whereFragment)
                order_by: {created_at: desc},
                limit: \(limit),
                offset: \(offset)
            ) {
                id
                event
                created_at
                data
                user_id
            }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            print("❌ [Feed] Failed to serialize request body")
            return []
        }
        req.httpBody = httpBody
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 [Feed] API response status: \(httpResponse.statusCode)")
            }
            
            // Debug: log raw response
            if let rawStr = String(data: data, encoding: .utf8) {
                print("📦 [Feed] Raw GraphQL response: \(rawStr.prefix(1000))")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ [Feed] Failed to parse JSON")
                return []
            }
            
            // Check for errors
            if let errors = json["errors"] as? [[String: Any]] {
                let messages = errors.compactMap { $0["message"] as? String }
                print("❌ [Feed] GraphQL errors: \(messages.joined(separator: ", "))")
                return []
            }
            
            guard let dataObj = json["data"] as? [String: Any],
                  let activities = dataObj["activities"] as? [[String: Any]] else {
                print("⚠️ [Feed] No activities in response")
                if let jsonStr = String(data: data, encoding: .utf8) {
                    print("📦 [Feed] Raw response: \(jsonStr.prefix(500))")
                }
                return []
            }
            
            print("✅ [Feed] Fetched \(activities.count) activities")
            
            // Debug: log unique event types
            let eventTypes = Set(activities.compactMap { $0["event"] as? String })
            print("📋 [Feed] Event types found: \(eventTypes.sorted())")
            // Debug: log first activity data
            if let first = activities.first {
                print("📋 [Feed] First activity: \(first)")
            }
            
            // Collect unique user IDs to batch-fetch user info
            let userIds = Set(activities.compactMap { $0["user_id"] as? Int })
            let userMap = await fetchUserInfoBatch(userIds: Array(userIds))
            
            var parsed = activities.compactMap { parseActivity($0, userMap: userMap) }
            
            // Batch-fetch book details for activities that have a bookId but no title
            let missingBookIds = Set(parsed.compactMap { activity -> Int? in
                guard activity.bookId != nil, activity.bookTitle == nil else { return nil }
                return activity.bookId
            })
            if !missingBookIds.isEmpty {
                let bookMap = await fetchBookInfoBatch(bookIds: Array(missingBookIds))
                parsed = parsed.map { activity in
                    guard let bid = activity.bookId, activity.bookTitle == nil,
                          let info = bookMap[bid] else { return activity }
                    return FeedActivity(
                        id: activity.id,
                        event: activity.event,
                        createdAt: activity.createdAt,
                        userId: activity.userId,
                        username: activity.username,
                        userImageURL: activity.userImageURL,
                        userFlair: activity.userFlair,
                        bookId: activity.bookId,
                        bookTitle: info.title,
                        bookImageURL: info.imageURL ?? activity.bookImageURL,
                        authorName: info.authorName ?? activity.authorName,
                        rating: activity.rating,
                        reviewText: activity.reviewText,
                        progress: activity.progress,
                        statusId: activity.statusId
                    )
                }
            }
            
            return parsed
            
        } catch {
            print("❌ [Feed] Network error: \(error)")
            return []
        }
    }
    
    // MARK: - Parse Activity
    
    private static func parseActivity(_ dict: [String: Any], userMap: [Int: FeedUserInfo]) -> FeedActivity? {
        guard let id = dict["id"] as? Int,
              let event = dict["event"] as? String,
              let createdAt = dict["created_at"] as? String else {
            return nil
        }
        
        let userId = dict["user_id"] as? Int
        
        // Get user info from batch-fetched map
        let userInfo = userId.flatMap { userMap[$0] }
        let username = userInfo?.username ?? "User \(userId ?? 0)"
        let userImage = userInfo?.imageURL
        let userFlair = userInfo?.flair
        
        // Parse data field (contains book info, status, review, etc.)
        // Parse data — may be a dictionary already, or a JSON string
        var activityData: [String: Any]?
        if let dataDict = dict["data"] as? [String: Any] {
            activityData = dataDict
        } else if let dataStr = dict["data"] as? String,
                  let dataBytes = dataStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: dataBytes) as? [String: Any] {
            activityData = parsed
        }
        
        // Extract book info — can be nested in different ways
        var bookId: Int?
        var bookTitle: String?
        var bookImageURL: String?
        var authorName: String?
        var rating: Double?
        var reviewText: String?
        var progress: Int?
        var statusId: Int?
        
        if let activityData = activityData {
            // Status ID
            statusId = activityData["status_id"] as? Int
                ?? activityData["statusId"] as? Int
            
            // Rating
            rating = activityData["rating"] as? Double
                ?? (activityData["rating"] as? Int).map { Double($0) }
            
            // Review
            reviewText = activityData["review"] as? String
                ?? activityData["review_text"] as? String
                ?? activityData["body"] as? String
            
            // Progress
            progress = activityData["progress"] as? Int
                ?? activityData["percentage"] as? Int
            
            // --- UserBookActivity: data contains userBook with edition info ---
            if event == "UserBookActivity" {
                if let userBook = activityData["user_book"] as? [String: Any] ?? activityData["userBook"] as? [String: Any] {
                    if statusId == nil {
                        statusId = userBook["status_id"] as? Int ?? userBook["statusId"] as? Int
                    }
                    // Rating from userBook
                    if rating == nil {
                        rating = userBook["rating"] as? Double
                            ?? (userBook["rating"] as? Int).map { Double($0) }
                    }
                    // Try book directly (some responses)
                    if let bookData = userBook["book"] as? [String: Any] {
                        bookId = bookData["id"] as? Int
                        bookTitle = bookData["title"] as? String
                        bookImageURL = (bookData["image"] as? [String: Any])?["url"] as? String
                        authorName = extractAuthorName(from: bookData)
                    }
                    // Try edition (most common in feed data)
                    if bookTitle == nil, let edition = userBook["edition"] as? [String: Any] {
                        if bookId == nil {
                            bookId = edition["bookId"] as? Int ?? edition["book_id"] as? Int
                        }
                        if bookTitle == nil {
                            bookTitle = edition["title"] as? String
                        }
                        if bookImageURL == nil {
                            bookImageURL = (edition["image"] as? [String: Any])?["url"] as? String
                        }
                        if authorName == nil {
                            // edition has contributions[].author.name
                            if let contribs = edition["contributions"] as? [[String: Any]] {
                                let names = contribs.compactMap { ($0["author"] as? [String: Any])?["name"] as? String }
                                if !names.isEmpty { authorName = names.joined(separator: ", ") }
                            }
                        }
                    }
                    // Fallback book_id
                    if bookId == nil {
                        bookId = userBook["book_id"] as? Int ?? userBook["bookId"] as? Int
                    }
                }
                // Also try direct book in data
                if bookTitle == nil, let bookData = activityData["book"] as? [String: Any] {
                    bookId = bookData["id"] as? Int
                    bookTitle = bookData["title"] as? String
                    bookImageURL = (bookData["image"] as? [String: Any])?["url"] as? String
                    authorName = extractAuthorName(from: bookData)
                }
            }
            
            // --- ListActivity: data contains list with listBooks array ---
            else if event == "ListActivity" {
                if let list = activityData["list"] as? [String: Any] {
                    let listName = list["name"] as? String
                    reviewText = listName  // Store list name for display
                    
                    // Get the first book from the list for display
                    if let listBooks = list["listBooks"] as? [[String: Any]],
                       let firstEntry = listBooks.first,
                       let bookData = firstEntry["book"] as? [String: Any] {
                        bookId = bookData["id"] as? Int
                        bookTitle = bookData["title"] as? String
                        bookImageURL = (bookData["image"] as? [String: Any])?["url"] as? String
                        authorName = extractAuthorName(from: bookData)
                    }
                }
            }
            
            // --- Generic fallback for other event types ---
            else {
                if let bookData = activityData["book"] as? [String: Any] {
                    bookId = bookData["id"] as? Int
                    bookTitle = bookData["title"] as? String
                    if let img = bookData["image"] as? [String: Any] {
                        bookImageURL = img["url"] as? String
                    }
                    authorName = extractAuthorName(from: bookData)
                }
                
                if bookId == nil {
                    bookId = activityData["book_id"] as? Int
                        ?? activityData["bookId"] as? Int
                }
                
                if bookTitle == nil {
                    bookTitle = activityData["book_title"] as? String
                        ?? activityData["title"] as? String
                }
                
                if let userBook = activityData["user_book"] as? [String: Any] {
                    if bookId == nil { bookId = userBook["book_id"] as? Int }
                    if let bookData = userBook["book"] as? [String: Any] {
                        if bookTitle == nil { bookTitle = bookData["title"] as? String }
                        if bookImageURL == nil {
                            bookImageURL = (bookData["image"] as? [String: Any])?["url"] as? String
                        }
                        if authorName == nil { authorName = extractAuthorName(from: bookData) }
                    }
                }
            }
        }
        
        print("📌 [Feed] Parsed activity #\(id): event=\(event) statusId=\(String(describing: statusId)) bookTitle=\(String(describing: bookTitle)) bookId=\(String(describing: bookId))")
        
        return FeedActivity(
            id: id,
            event: event,
            createdAt: createdAt,
            userId: userId,
            username: username,
            userImageURL: userImage,
            userFlair: userFlair,
            bookId: bookId,
            bookTitle: bookTitle,
            bookImageURL: bookImageURL,
            authorName: authorName,
            rating: rating,
            reviewText: reviewText,
            progress: progress,
            statusId: statusId
        )
    }
    
    // MARK: - Helper: Get current user ID
    
    /// Extract author name from a book dictionary, trying multiple known paths.
    private static func extractAuthorName(from bookData: [String: Any]) -> String? {
        // Try cachedContributors (used in activities data)
        if let cached = bookData["cachedContributors"] as? [[String: Any]] {
            let names = cached.compactMap { ($0["author"] as? [String: Any])?["name"] as? String }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        // Try contributions (used in GraphQL queries)
        if let contributions = bookData["contributions"] as? [[String: Any]] {
            let names = contributions.compactMap { ($0["author"] as? [String: Any])?["name"] as? String }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        // Try direct author field
        if let author = bookData["author"] as? String { return author }
        if let author = (bookData["author"] as? [String: Any])?["name"] as? String { return author }
        return nil
    }
    
    private static func fetchCurrentUserId() async -> Int? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = "{ me { id } }"
        let body: [String: Any] = ["query": query]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let me = dataObj["me"] as? [[String: Any]],
               let first = me.first,
               let id = first["id"] as? Int {
                return id
            }
        } catch {
            print("❌ [Feed] Failed to fetch current user ID: \(error)")
        }
        return nil
    }
    
    // MARK: - Batch fetch book info
    
    private struct FeedBookInfo {
        let id: Int
        let title: String
        let imageURL: String?
        let authorName: String?
    }
    
    /// Fetch book info for a batch of book IDs in one GraphQL call.
    private static func fetchBookInfoBatch(bookIds: [Int]) async -> [Int: FeedBookInfo] {
        guard !bookIds.isEmpty else { return [:] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [:] }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let idsString = bookIds.map { String($0) }.joined(separator: ", ")
        let query = """
        {
            books(where: {id: {_in: [\(idsString)]}}) {
                id
                title
                cached_contributors
                image {
                    url
                }
            }
        }
        """
        
        let body: [String: Any] = ["query": query]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return [:] }
        req.httpBody = httpBody
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let books = dataObj["books"] as? [[String: Any]] else {
                print("⚠️ [Feed] No books in batch response")
                return [:]
            }
            
            var map: [Int: FeedBookInfo] = [:]
            for book in books {
                guard let id = book["id"] as? Int,
                      let title = book["title"] as? String else { continue }
                let imageURL = (book["image"] as? [String: Any])?["url"] as? String
                let authorName = extractAuthorName(from: book)
                map[id] = FeedBookInfo(id: id, title: title, imageURL: imageURL, authorName: authorName)
            }
            print("✅ [Feed] Batch fetched \(map.count) books for feed")
            return map
        } catch {
            print("❌ [Feed] Failed to batch fetch book info: \(error)")
            return [:]
        }
    }
    
    // MARK: - Batch fetch user info
    
    private struct FeedUserInfo {
        let id: Int
        let username: String
        let imageURL: String?
        let flair: String?
    }
    
    /// Fetch user info for a batch of user IDs in one GraphQL call.
    private static func fetchUserInfoBatch(userIds: [Int]) async -> [Int: FeedUserInfo] {
        guard !userIds.isEmpty else { return [:] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [:] }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let idsString = userIds.map { String($0) }.joined(separator: ", ")
        let query = """
        {
            users(where: {id: {_in: [\(idsString)]}}) {
                id
                username
                image {
                    url
                }
                flair
            }
        }
        """
        
        let body: [String: Any] = ["query": query]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return [:] }
        req.httpBody = httpBody
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let users = dataObj["users"] as? [[String: Any]] else {
                return [:]
            }
            
            var map: [Int: FeedUserInfo] = [:]
            for user in users {
                guard let id = user["id"] as? Int,
                      let username = user["username"] as? String else { continue }
                let imageURL = (user["image"] as? [String: Any])?["url"] as? String
                let flair = user["flair"] as? String
                map[id] = FeedUserInfo(id: id, username: username, imageURL: imageURL, flair: flair)
            }
            return map
        } catch {
            print("❌ [Feed] Failed to batch fetch user info: \(error)")
            return [:]
        }
    }
}
