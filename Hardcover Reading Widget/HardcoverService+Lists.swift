import Foundation

// MARK: - User Lists Models
struct UserList: Identifiable, Codable {
    let id: Int
    let name: String
    let description: String?
    let booksCount: Int?
    let likesCount: Int?
    let slug: String?
    let user: ListUser?
    let coverImage: ListCoverImage?

    enum CodingKeys: String, CodingKey {
        case id, name, description, slug, user
        case booksCount = "books_count"
        case likesCount = "likes_count"
        case coverImage = "cover_image"
    }
}

struct ListUser: Codable {
    let id: Int?
    let username: String?
}

struct ListCoverImage: Codable {
    let url: String?
}

struct ListBook: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let author: String?
    let coverUrl: String?
    let bookId: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, author
        case coverUrl = "cover_url"
        case bookId = "book_id"
    }

    func toBookProgress() -> BookProgress {
        return BookProgress(
            id: "\(bookId ?? id)",
            title: title,
            author: author ?? "Unknown Author",
            coverImageData: nil,
            coverImageUrl: coverUrl,
            progress: 0.0,
            totalPages: 0,
            currentPage: 0,
            bookId: bookId ?? id,
            userBookId: nil,
            editionId: id,
            originalTitle: title,
            editionAverageRating: nil,
            userRating: nil,
            bookDescription: nil
        )
    }
}

extension HardcoverService {
    /// Fetch lists for any user by parsing their lists page
    static func fetchUserLists(username: String) async -> [UserList] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key available")
            return []
        }

        guard let url = URL(string: "https://hardcover.app/@\(username)/lists") else {
            print("❌ Invalid URL")
            return []
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)

            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ Could not decode HTML")
                return []
            }

            // Extract lists from HTML
            if let lists = extractListsFromHTML(html) {
                print("✅ Fetched \(lists.count) lists for @\(username)")
                return lists
            }

            return []
        } catch {
            print("❌ Failed to fetch user lists: \(error)")
            return []
        }
    }

    /// Extract lists from Inertia.js data-page attribute
    private static func extractListsFromHTML(_ html: String) -> [UserList]? {
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

        print("📦 JSON preview: \(String(jsonString.prefix(1000)))")

        // Try to decode to see what structure we have
        if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let props = jsonObject["props"] as? [String: Any] {
            print("📊 Props keys: \(props.keys.joined(separator: ", "))")

            if let lists = props["lists"] as? [[String: Any]] {
                print("📋 Found \(lists.count) lists")

                // Decode lists manually
                do {
                    let listsData = try JSONSerialization.data(withJSONObject: lists)
                    let decoder = JSONDecoder()
                    let userLists = try decoder.decode([UserList].self, from: listsData)
                    return userLists
                } catch {
                    print("❌ Failed to decode lists: \(error)")
                    return nil
                }
            }
        }

        print("⚠️ Could not extract lists from page data")
        return nil
    }

    /// Fetch books in a specific list
    static func fetchListBooks(username: String, listSlug: String) async -> [ListBook] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key available")
            return []
        }

        guard let url = URL(string: "https://hardcover.app/@\(username)/lists/\(listSlug)") else {
            print("❌ Invalid URL")
            return []
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)

            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ Could not decode HTML")
                return []
            }

            // Extract books from HTML
            if let books = extractListBooksFromHTML(html) {
                print("✅ Fetched \(books.count) books from list")
                return books
            }

            return []
        } catch {
            print("❌ Failed to fetch list books: \(error)")
            return []
        }
    }

    /// Extract books from list detail page
    private static func extractListBooksFromHTML(_ html: String) -> [ListBook]? {
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

        // Try to decode to see what structure we have
        if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let props = jsonObject["props"] as? [String: Any] {
            print("📊 Props keys: \(props.keys.joined(separator: ", "))")

            // Debug letterbooks structure
            if let letterbooks = props["letterbooks"] {
                print("🔍 letterbooks type: \(type(of: letterbooks))")
                if let letterbooksDict = letterbooks as? [String: Any] {
                    print("🔍 letterbooks is dict with keys: \(letterbooksDict.keys.joined(separator: ", "))")

                    // Try nested letterbooks.letterbooks array
                    if let nestedLetterbooks = letterbooksDict["letterbooks"] as? [[String: Any]] {
                        print("📚 Found \(nestedLetterbooks.count) books in letterbooks.letterbooks")
                        return parseBooks(nestedLetterbooks)
                    }

                    // Try to get data from pagination structure
                    if let data = letterbooksDict["data"] as? [[String: Any]] {
                        print("📚 Found \(data.count) books in letterbooks.data")
                        return parseBooks(data)
                    }
                } else if let letterbooksArray = letterbooks as? [[String: Any]] {
                    print("📚 Found \(letterbooksArray.count) books in letterbooks array")
                    return parseBooks(letterbooksArray)
                }
            }

            // Try books as fallback
            if let books = props["books"] as? [[String: Any]] {
                print("📚 Found \(books.count) books in books array")
                return parseBooks(books)
            }
        }

        print("⚠️ Could not extract books from page data")
        return nil
    }

    /// Parse books from array of dictionaries
    private static func parseBooks(_ books: [[String: Any]]) -> [ListBook] {
        var listBooks: [ListBook] = []

        // Debug first book structure
        if let firstBook = books.first {
            print("🔍 First book keys: \(firstBook.keys.joined(separator: ", "))")
            if let jsonData = try? JSONSerialization.data(withJSONObject: firstBook),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let preview = String(jsonString.prefix(500))
                print("📖 First book preview: \(preview)")
            }
        }

        for bookDict in books {
            // Try to get edition data
            guard let edition = bookDict["edition"] as? [String: Any],
                  let editionId = edition["id"] as? Int,
                  let rawTitle = edition["title"] as? String else {
                continue
            }

            let title = rawTitle.decodedHTMLEntities

            // Get author name
            var authorName: String?
            if let contributions = edition["contributions"] as? [[String: Any]],
               let firstContribution = contributions.first,
               let author = firstContribution["author"] as? [String: Any],
               let name = author["name"] as? String {
                authorName = name
            }

            // Get cover image
            var coverUrl: String?
            if let image = edition["image"] as? [String: Any],
               let url = image["url"] as? String {
                coverUrl = url
            }

            // Get book ID from book object or edition
            var bookId: Int?
            if let book = bookDict["book"] as? [String: Any],
               let id = book["id"] as? Int {
                bookId = id
            } else {
                bookId = edition["book_id"] as? Int
            }

            let listBook = ListBook(
                id: editionId,
                title: title,
                author: authorName,
                coverUrl: coverUrl,
                bookId: bookId
            )
            listBooks.append(listBook)
        }

        return listBooks
    }

    // MARK: - Community Lists

    /// Fetch community lists (featured or popular)
    static func fetchCommunityLists(filter: String) async -> [CommunityList] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ fetchCommunityLists: No API key available")
            return []
        }

        // Use filter to get featured or popular lists
        let endpoint = filter == "featured" ? "https://hardcover.app/lists" : "https://hardcover.app/lists/\(filter)"
        guard let url = URL(string: endpoint) else {
            print("❌ fetchCommunityLists: Invalid URL: \(endpoint)")
            return []
        }

        print("[Lists] Fetching \(filter) lists from: \(endpoint)")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30 // Add timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: req)

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                print("[Lists] Status code: \(httpResponse.statusCode)")
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("❌ HTTP error: \(httpResponse.statusCode)")
                    return []
                }
            }

            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ Could not decode HTML response")
                return []
            }

            print("[Lists] HTML length: \(html.count) characters")

            // Extract community lists from HTML
            if let lists = extractCommunityListsFromHTML(html) {
                print("[Lists] Successfully fetched \(lists.count) \(filter) community lists")
                return lists
            } else {
                print("❌ Failed to extract lists from HTML")
            }

            return []
        } catch let error as URLError {
            print("❌ Network error fetching community lists: \(error.localizedDescription) (code: \(error.code.rawValue))")
            return []
        } catch {
            print("❌ Unexpected error fetching community lists: \(error)")
            return []
        }
    }

    /// Extract community lists from Inertia.js data-page attribute
    private static func extractCommunityListsFromHTML(_ html: String) -> [CommunityList]? {
        // Find data-page attribute
        guard let dataPageRange = html.range(of: "data-page=\"") else {
            print("❌ Could not find data-page attribute in HTML")
            // Check if it's an error page
            if html.contains("Something went wrong") || html.contains("error") {
                print("[Lists] HTML appears to be an error page")
            }
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

        print("[Lists] JSON string length: \(jsonString.count)")

        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Could not convert JSON string to data")
            return nil
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("❌ Could not parse root JSON object")
                return nil
            }

            print("[Lists] JSON keys: \(json.keys.joined(separator: ", "))")

            guard let props = json["props"] as? [String: Any] else {
                print("❌ Could not find 'props' in JSON")
                return nil
            }

            print("[Lists] Props keys: \(props.keys.joined(separator: ", "))")

            guard let listsArray = props["lists"] as? [[String: Any]] else {
                print("❌ Could not find 'lists' array in props")
                // Try alternative structures
                if let listData = props["list"] as? [String: Any] {
                    print("[Lists] Found 'list' (singular) instead of 'lists'")
                }
                return nil
            }

            print("[Lists] Found \(listsArray.count) lists in JSON")

            var communityLists: [CommunityList] = []

            for listDict in listsArray {
                guard let id = listDict["id"] as? Int,
                      let name = listDict["name"] as? String else {
                    continue
                }

                let description = listDict["description"] as? String
                let bookCount = listDict["booksCount"] as? Int ?? 0

                // Extract creator info
                var creatorUsername = "unknown"
                var creatorImage: String?
                if let user = listDict["user"] as? [String: Any] {
                    creatorUsername = user["username"] as? String ?? "unknown"
                    // Try "image" first, then "cachedImage"
                    if let image = user["image"] as? [String: Any],
                       let url = image["url"] as? String {
                        creatorImage = url
                    } else if let cachedImage = user["cachedImage"] as? [String: Any],
                              let url = cachedImage["url"] as? String {
                        creatorImage = url
                    }
                }

                // Extract book covers (up to 3) and all books from listBooks
                var bookCovers: [String] = []
                var books: [ListBook] = []

                if let listBooks = listDict["listBooks"] as? [[String: Any]] {
                    // Get covers for display (up to 3)
                    for listBook in listBooks.prefix(3) {
                        if let book = listBook["book"] as? [String: Any],
                           let image = book["image"] as? [String: Any],
                           let url = image["url"] as? String {
                            bookCovers.append(url)
                        }
                    }

                    // Extract all books for detail view
                    for listBook in listBooks {
                        guard let book = listBook["book"] as? [String: Any],
                              let bookId = book["id"] as? Int,
                              let rawTitle = book["title"] as? String else {
                            continue
                        }

                        let title = rawTitle.decodedHTMLEntities

                        // Get author
                        var authorName: String?
                        if let contributions = book["contributions"] as? [[String: Any]],
                           let firstContribution = contributions.first,
                           let author = firstContribution["author"] as? [String: Any],
                           let name = author["name"] as? String {
                            authorName = name
                        }

                        // Get cover URL
                        var coverUrl: String?
                        if let image = book["image"] as? [String: Any],
                           let url = image["url"] as? String {
                            coverUrl = url
                        }

                        // Get edition ID from listBook
                        let editionId = listBook["editionId"] as? Int ?? bookId

                        let listBookObj = ListBook(
                            id: editionId,
                            title: title,
                            author: authorName,
                            coverUrl: coverUrl,
                            bookId: bookId
                        )

                        books.append(listBookObj)
                    }
                }

                let communityList = CommunityList(
                    id: id,
                    name: name,
                    description: description,
                    creatorUsername: creatorUsername,
                    creatorImage: creatorImage,
                    bookCount: bookCount,
                    bookCovers: bookCovers,
                    books: books
                )

                communityLists.append(communityList)
            }

            return communityLists
        } catch {
            print("❌ JSON parsing error: \(error)")
            return nil
        }
    }

    /// Fetch books in a community list
    static func fetchCommunityListBooks(listId: Int) async -> [ListBook] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key available")
            return []
        }

        guard let url = URL(string: "https://hardcover.app/lists/\(listId)") else {
            print("❌ Invalid URL")
            return []
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)

            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ Could not decode HTML")
                return []
            }

            // Reuse the existing extraction method
            if let books = extractListBooksFromHTML(html) {
                print("✅ Fetched \(books.count) books for community list \(listId)")
                return books
            }

            return []
        } catch {
            print("❌ Failed to fetch community list books: \(error)")
            return []
        }
    }

    // MARK: - Community Upcoming Releases

    /// Fetch popular upcoming releases from community
    static func fetchCommunityUpcomingReleases(filter: String) async -> [CommunityUpcomingBook] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key configured for community upcoming releases")
            return []
        }

        let limit = 25

        let popularBooks = await fetchCommunityUpcomingBooks(limit: limit)
        if !popularBooks.isEmpty {
            return popularBooks
        }

        return await fetchCommunityUpcomingEditions(limit: limit)
    }

    private static func fetchCommunityUpcomingBooks(limit: Int) async -> [CommunityUpcomingBook] {
        let query = """
        query CommunityUpcomingBooks($today: date!, $limit: Int!) {
          books(
            where: {
              release_date: { _gte: $today }
            },
            order_by: [{ users_count: desc }, { release_date: asc }],
            limit: $limit
          ) {
            id
            title
            release_date
            users_count
            users_read_count
            contributions(limit: 1) { author { name } }
            image { url }
          }
        }
        """

        guard let root = await performCommunityUpcomingGraphQL(
            query: query,
            variables: [
                "today": communityUpcomingDateString(Date()),
                "limit": max(limit, 1)
            ]
        ),
              let data = root["data"] as? [String: Any],
              let rows = data["books"] as? [[String: Any]] else {
            return []
        }

        return rows.compactMap { makeCommunityUpcomingBook(fromBook: $0) }
    }

    private static func fetchCommunityUpcomingEditions(limit: Int) async -> [CommunityUpcomingBook] {
        let query = """
        query CommunityUpcomingEditions($today: date!, $limit: Int!) {
          editions(
            where: {
              release_date: { _gte: $today }
            },
            order_by: [{ users_count: desc }, { release_date: asc }],
            limit: $limit
          ) {
            id
            book_id
            title
            release_date
            users_count
            users_read_count
            contributions(limit: 1) { author { name } }
            image { url }
            book {
              id
              title
              release_date
              users_count
              users_read_count
              contributions(limit: 1) { author { name } }
              image { url }
            }
          }
        }
        """

        guard let root = await performCommunityUpcomingGraphQL(
            query: query,
            variables: [
                "today": communityUpcomingDateString(Date()),
                "limit": max(limit * 4, 80)
            ]
        ),
              let data = root["data"] as? [String: Any],
              let rows = data["editions"] as? [[String: Any]] else {
            return []
        }

        var booksById: [Int: CommunityUpcomingBook] = [:]

        for row in rows {
            guard let book = makeCommunityUpcomingBook(fromEdition: row) else {
                continue
            }

            if let existing = booksById[book.id] {
                if shouldReplaceCommunityUpcomingBook(existing, with: book) {
                    booksById[book.id] = book
                }
            } else {
                booksById[book.id] = book
            }
        }

        let books = booksById.values.sorted { lhs, rhs in
            if lhs.contributionsCount != rhs.contributionsCount {
                return lhs.contributionsCount > rhs.contributionsCount
            }
            return (lhs.releaseDate ?? "") < (rhs.releaseDate ?? "")
        }

        return Array(books.prefix(limit))
    }

    private static func communityUpcomingDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func performCommunityUpcomingGraphQL(query: String, variables: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("Softcover iOS", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "query": query,
                "variables": variables
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("❌ Community upcoming GraphQL HTTP \(http.statusCode)")
                return nil
            }

            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let error = root["error"] as? String, !error.isEmpty {
                print("❌ Community upcoming GraphQL Error: \(error)")
                return nil
            }

            if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
                for error in errors {
                    if let message = error["message"] as? String {
                        print("❌ Community upcoming GraphQL Error: \(message)")
                    }
                }
                return nil
            }

            return root
        } catch {
            print("❌ Community upcoming GraphQL request failed: \(error)")
            return nil
        }
    }

    private static func makeCommunityUpcomingBook(fromBook dict: [String: Any]) -> CommunityUpcomingBook? {
        guard let id = communityUpcomingIntValue(dict["id"]) else {
            return nil
        }

        let rawTitle = dict["title"] as? String ?? "Unknown Title"
        let title = rawTitle.decodedHTMLEntities
        let author = communityUpcomingAuthorName(from: dict["contributions"])
            ?? communityUpcomingAuthorName(from: dict["cached_contributors"])
            ?? "Unknown Author"
        let coverUrl = communityUpcomingImageUrl(from: dict["image"])
            ?? communityUpcomingImageUrl(from: dict["cached_image"])
        let releaseDate = dict["release_date"] as? String
        let usersCount = communityUpcomingIntValue(dict["users_count"])
            ?? communityUpcomingIntValue(dict["users_read_count"])
            ?? 0

        return CommunityUpcomingBook(
            id: id,
            title: title,
            author: author,
            coverUrl: coverUrl,
            releaseDate: releaseDate,
            contributionsCount: usersCount
        )
    }

    private static func makeCommunityUpcomingBook(fromEdition row: [String: Any]) -> CommunityUpcomingBook? {
        let bookDict = row["book"] as? [String: Any]
        let editionId = communityUpcomingIntValue(row["id"])
        guard let id = communityUpcomingIntValue(row["book_id"]) ?? communityUpcomingIntValue(bookDict?["id"]) ?? editionId else {
            return nil
        }

        let rawTitle = (bookDict?["title"] as? String) ?? (row["title"] as? String) ?? "Unknown Title"
        let title = rawTitle.decodedHTMLEntities
        let author = communityUpcomingAuthorName(from: row["contributions"])
            ?? communityUpcomingAuthorName(from: bookDict?["contributions"])
            ?? communityUpcomingAuthorName(from: row["cached_contributors"])
            ?? communityUpcomingAuthorName(from: bookDict?["cached_contributors"])
            ?? "Unknown Author"
        let coverUrl = communityUpcomingImageUrl(from: row["image"])
            ?? communityUpcomingImageUrl(from: bookDict?["image"])
            ?? communityUpcomingImageUrl(from: row["cached_image"])
            ?? communityUpcomingImageUrl(from: bookDict?["cached_image"])
        let releaseDate = (row["release_date"] as? String) ?? (bookDict?["release_date"] as? String)
        let usersCount = communityUpcomingIntValue(row["users_count"])
            ?? communityUpcomingIntValue(bookDict?["users_count"])
            ?? communityUpcomingIntValue(row["users_read_count"])
            ?? communityUpcomingIntValue(bookDict?["users_read_count"])
            ?? 0

        return CommunityUpcomingBook(
            id: id,
            title: title,
            author: author,
            coverUrl: coverUrl,
            releaseDate: releaseDate,
            contributionsCount: usersCount
        )
    }

    private static func shouldReplaceCommunityUpcomingBook(_ existing: CommunityUpcomingBook, with candidate: CommunityUpcomingBook) -> Bool {
        if candidate.contributionsCount != existing.contributionsCount {
            return candidate.contributionsCount > existing.contributionsCount
        }
        return (candidate.releaseDate ?? "") < (existing.releaseDate ?? "")
    }

    private static func communityUpcomingIntValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let string = value as? String {
            return Int(string)
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func communityUpcomingImageUrl(from value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }

        guard let dict = value as? [String: Any] else {
            return nil
        }

        if let url = dict["url"] as? String, !url.isEmpty {
            return url
        }
        if let small = dict["small"] as? [String: Any],
           let url = small["url"] as? String,
           !url.isEmpty {
            return url
        }
        if let medium = dict["medium"] as? [String: Any],
           let url = medium["url"] as? String,
           !url.isEmpty {
            return url
        }

        return nil
    }

    private static func communityUpcomingAuthorName(from value: Any?) -> String? {
        if let names = value as? [String] {
            return names.first { !$0.isEmpty }
        }

        if let contributors = value as? [[String: Any]] {
            for contributor in contributors {
                if let name = contributor["name"] as? String, !name.isEmpty {
                    return name
                }
                if let name = contributor["author_name"] as? String, !name.isEmpty {
                    return name
                }
                if let author = contributor["author"] as? [String: Any],
                   let name = author["name"] as? String,
                   !name.isEmpty {
                    return name
                }
            }
        }

        if let dict = value as? [String: Any] {
            if let name = dict["name"] as? String, !name.isEmpty {
                return name
            }
            if let name = dict["author_name"] as? String, !name.isEmpty {
                return name
            }
            if let authors = dict["authors"] as? [[String: Any]] {
                return communityUpcomingAuthorName(from: authors)
            }
        }

        return nil
    }
}
