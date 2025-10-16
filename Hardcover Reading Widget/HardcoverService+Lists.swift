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
            print("❌ No API key available")
            return []
        }
        
        // Use filter to get featured or popular lists
        let endpoint = filter == "featured" ? "https://hardcover.app/lists" : "https://hardcover.app/lists/\(filter)"
        guard let url = URL(string: endpoint) else {
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
            
            // Extract community lists from HTML
            if let lists = extractCommunityListsFromHTML(html) {
                print("✅ Fetched \(lists.count) \(filter) community lists")
                return lists
            }
            
            return []
        } catch {
            print("❌ Failed to fetch community lists: \(error)")
            return []
        }
    }
    
    /// Extract community lists from Inertia.js data-page attribute
    private static func extractCommunityListsFromHTML(_ html: String) -> [CommunityList]? {
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
                  let listsArray = props["lists"] as? [[String: Any]] else {
                print("❌ Could not parse lists from JSON")
                return nil
            }
            
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
            print("❌ No API key available")
            return []
        }
        
        guard let url = URL(string: "https://hardcover.app/upcoming/\(filter)") else {
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
            
            // Extract upcoming releases from HTML
            if let books = extractCommunityUpcomingFromHTML(html) {
                print("✅ Fetched \(books.count) community upcoming releases (\(filter))")
                return books
            }
            
            return []
        } catch {
            print("❌ Failed to fetch community upcoming releases: \(error)")
            return []
        }
    }
    
    /// Extract community upcoming releases from Inertia.js data-page attribute
    private static func extractCommunityUpcomingFromHTML(_ html: String) -> [CommunityUpcomingBook]? {
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
                print("❌ Could not parse upcoming books from JSON")
                return nil
            }
            
            var upcomingBooks: [CommunityUpcomingBook] = []
            
            for bookDict in booksArray {
                // Books are directly in the array, not nested under "book"
                guard let id = bookDict["id"] as? Int,
                      let rawTitle = bookDict["title"] as? String else {
                    continue
                }
                
                let title = rawTitle.decodedHTMLEntities
                
                // Get author
                var authorName = "Unknown Author"
                if let contributions = bookDict["contributions"] as? [[String: Any]],
                   let firstContribution = contributions.first,
                   let author = firstContribution["author"] as? [String: Any],
                   let name = author["name"] as? String {
                    authorName = name
                }
                
                // Get cover image
                var coverUrl: String?
                if let image = bookDict["image"] as? [String: Any],
                   let url = image["url"] as? String {
                    coverUrl = url
                }
                
                // Get release date
                var releaseDate: String?
                if let release = bookDict["releaseDate"] as? String {
                    releaseDate = release
                }
                
                // Get users count (people reading/waiting)
                let contributionsCount = bookDict["usersCount"] as? Int ?? 0
                
                let upcomingBook = CommunityUpcomingBook(
                    id: id,
                    title: title,
                    author: authorName,
                    coverUrl: coverUrl,
                    releaseDate: releaseDate,
                    contributionsCount: contributionsCount
                )
                
                upcomingBooks.append(upcomingBook)
            }
            
            return upcomingBooks
        } catch {
            print("❌ JSON parsing error: \(error)")
            return nil
        }
    }
}
