import Foundation

extension HardcoverService {
    /// Fetch trending books for a specific time period via HTML scraping
    static func fetchTrendingBooks(timeFilter: String) async -> [TrendingBook] {
        let urlString = "https://hardcover.app/trending/\(timeFilter)"
        print("📡 Fetching trending: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid trending URL")
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    print("❌ Non-200 status code for \(timeFilter)")
                    return []
                }
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ Non-200 status code")
                return []
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ Could not decode HTML")
                return []
            }
            
            // Debug: print first 500 chars
            let preview = String(html.prefix(500))
            print("📄 HTML preview: \(preview)")
            
            return extractTrendingFromHTML(html)
            
        } catch {
            print("❌ Trending fetch failed: \(error)")
            return []
        }
    }
    
    private static func extractTrendingFromHTML(_ html: String) -> [TrendingBook] {
        // Find data-page attribute - try simple string search first
        guard let dataPageStart = html.range(of: "data-page=\"") else {
            print("❌ Could not find data-page attribute")
            // Try to find any script tag with data
            if let scriptStart = html.range(of: "<script") {
                let scriptPreview = String(html[scriptStart.lowerBound..<html.index(scriptStart.lowerBound, offsetBy: min(200, html.count - html.distance(from: html.startIndex, to: scriptStart.lowerBound)))])
                print("📄 Script preview: \(scriptPreview)")
            }
            return []
        }
        
        let jsonStartIndex = dataPageStart.upperBound
        guard let jsonEndIndex = html[jsonStartIndex...].range(of: "\"") else {
            print("❌ Could not find end quote")
            return []
        }
        
        let jsonString = String(html[jsonStartIndex..<jsonEndIndex.lowerBound])
        
        // Decode HTML entities
        let decodedJSON = jsonString
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        
        guard let jsonData = decodedJSON.data(using: .utf8) else {
            print("❌ Could not convert to data")
            return []
        }
        
        do {
            guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let props = root["props"] as? [String: Any],
                  let booksArray = props["books"] as? [[String: Any]] else {
                print("❌ Could not parse structure")
                return []
            }
            
            var books: [TrendingBook] = []
            
            // Debug: print first book structure
            if let firstBook = booksArray.first {
                print("📖 First book structure:")
                print("  Keys: \(firstBook.keys)")
                if let image = firstBook["cachedImage"] {
                    print("  cachedImage: \(image)")
                }
                if let image = firstBook["image"] {
                    print("  image: \(image)")
                }
            }
            
            for bookDict in booksArray {
                guard let id = bookDict["id"] as? Int,
                      let rawTitle = bookDict["title"] as? String else {
                    continue
                }
                
                let title = rawTitle.decodedHTMLEntities
                
                var author = "Unknown Author"
                if let contributions = bookDict["contributions"] as? [[String: Any]],
                   let firstContribution = contributions.first,
                   let authorDict = firstContribution["author"] as? [String: Any],
                   let authorName = authorDict["name"] as? String {
                    author = authorName
                }
                
                let usersCount = (bookDict["usersCount"] as? Int) ?? 0
                
                // Get image URL - try both "image" and "cachedImage" fields
                var imageUrl: String?
                if let imageDict = bookDict["image"] as? [String: Any],
                   let url = imageDict["url"] as? String,
                   !url.isEmpty {
                    imageUrl = url
                } else if let cachedImage = bookDict["cachedImage"] as? [String: Any],
                          let url = cachedImage["url"] as? String,
                          !url.isEmpty {
                    imageUrl = url
                }
                
                let book = TrendingBook(
                    id: id,
                    title: title,
                    author: author,
                    coverImageUrl: imageUrl,
                    usersCount: usersCount
                )
                
                books.append(book)
            }
            
            print("✅ Parsed \(books.count) trending books")
            return books
            
        } catch {
            print("❌ JSON parsing failed: \(error)")
            return []
        }
    }
}
