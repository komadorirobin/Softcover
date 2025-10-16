import SwiftUI
import Foundation

// MARK: - Compatibility Functions
// These functions maintain compatibility with existing code that expects file-scoped functions

fileprivate func extractGenres(_ value: Any?) -> [String]? {
    BookTagExtractor.extractGenres(value)
}

fileprivate func extractGenres(fromCachedTags value: Any?) -> [String]? {
    BookTagExtractor.extractGenres(fromCachedTags: value)
}

fileprivate func extractMoods(_ value: Any?) -> [String]? {
    BookTagExtractor.extractMoods(value)
}

fileprivate func extractMoods(fromCachedTags value: Any?) -> [String]? {
    BookTagExtractor.extractMoods(fromCachedTags: value)
}

fileprivate func extractGenresFromTaggings(_ value: Any?) -> [String]? {
    BookTagExtractor.extractGenresFromTaggings(value)
}

fileprivate func extractMoodsFromTaggings(_ value: Any?) -> [String]? {
    BookTagExtractor.extractMoodsFromTaggings(value)
}

// MARK: - Query Helper Functions
// These delegate to BookMetadataService for cleaner code

fileprivate func queryBookCachedGenres(url: URL, bookId: Int) async -> [String]? {
    await BookMetadataService.queryBookCachedGenres(url: url, bookId: bookId)
}

fileprivate func queryUserBookCachedGenres(url: URL, userBookId: Int) async -> [String]? {
    await BookMetadataService.queryUserBookCachedGenres(url: url, userBookId: userBookId)
}

fileprivate func queryBookMoodsViaTaggings(url: URL, bookId: Int) async -> [String]? {
    await BookMetadataService.queryBookMoodsViaTaggings(url: url, bookId: bookId)
}

fileprivate func queryEditionBookMoodsViaTaggings(url: URL, editionId: Int) async -> [String]? {
    await BookMetadataService.queryEditionBookMoodsViaTaggings(url: url, editionId: editionId)
}

fileprivate func queryUserBookMoodsViaTaggings(url: URL, userBookId: Int) async -> [String]? {
    await BookMetadataService.queryUserBookMoodsViaTaggings(url: url, userBookId: userBookId)
}

fileprivate func queryBookCachedMoods(url: URL, bookId: Int) async -> [String]? {
    await BookMetadataService.queryBookCachedMoods(url: url, bookId: bookId)
}

fileprivate func queryEditionBookCachedMoods(url: URL, editionId: Int) async -> [String]? {
    await BookMetadataService.queryEditionBookCachedMoods(url: url, editionId: editionId)
}

fileprivate func queryUserBookCachedMoods(url: URL, userBookId: Int) async -> [String]? {
    await BookMetadataService.queryUserBookCachedMoods(url: url, userBookId: userBookId)
}

// MARK: - BookMetadataService
// Centralized static API used by the helpers above

struct BookMetadataService {
    // MARK: cached_tags (Genres)
    static func queryBookCachedGenres(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            cached_tags
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractGenres(fromCachedTags: first["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    static func queryUserBookCachedGenres(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
            edition { id book { id cached_tags } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first {
                if let book = first["book"] as? [String: Any],
                   let arr = extractGenres(fromCachedTags: book["cached_tags"]),
                   !arr.isEmpty {
                    return arr
                }
                // Intentionally do not fall back to edition.book for genres.
            }
        } catch { return nil }
        return nil
    }
    
    // MARK: taggings (Moods)
    static func queryBookMoodsViaTaggings(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            taggings(limit: 200) { tag { tag tag_category { slug } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractMoodsFromTaggings(first["taggings"])
            }
        } catch { return nil }
        return nil
    }
    
    static func queryEditionBookMoodsViaTaggings(url: URL, editionId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          editions(where: { id: { _eq: $id }}) {
            id
            book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": editionId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let editions = dataDict["editions"] as? [[String: Any]],
               let first = editions.first,
               let book = first["book"] as? [String: Any] {
                return extractMoodsFromTaggings(book["taggings"])
            }
        } catch { return nil }
        return nil
    }
    
    static func queryUserBookMoodsViaTaggings(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
            edition { id book { id taggings(limit: 200) { tag { tag tag_category { slug } } } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first {
                if let book = first["book"] as? [String: Any],
                   let arr = extractMoodsFromTaggings(book["taggings"]),
                   !arr.isEmpty { return arr }
                if let ed = first["edition"] as? [String: Any],
                   let b = ed["book"] as? [String: Any],
                   let arr = extractMoodsFromTaggings(b["taggings"]),
                   !arr.isEmpty { return arr }
            }
        } catch { return nil }
        return nil
    }
    
    // MARK: cached_tags (Moods)
    static func queryBookCachedMoods(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            cached_tags
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractMoods(fromCachedTags: first["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    static func queryEditionBookCachedMoods(url: URL, editionId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          editions(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": editionId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let editions = dataDict["editions"] as? [[String: Any]],
               let first = editions.first,
               let book = first["book"] as? [String: Any] {
                return extractMoods(fromCachedTags: book["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    static func queryUserBookCachedMoods(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
            edition { id book { id cached_tags } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first {
                if let book = first["book"] as? [String: Any],
                   let arr = extractMoods(fromCachedTags: book["cached_tags"]),
                   !arr.isEmpty { return arr }
                if let ed = first["edition"] as? [String: Any],
                   let b = ed["book"] as? [String: Any],
                   let arr = extractMoods(fromCachedTags: b["cached_tags"]),
                   !arr.isEmpty { return arr }
            }
        } catch { return nil }
        return nil
    }
    
    // MARK: - Instance API expected by SearchBooksView
    // Returns the subset of input bookIds that are finished (status_id == 3) for the current user.
    func fetchFinishedBookIds(for bookIds: [Int]) async -> [Int] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard !bookIds.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        // Step 1: fetch current user's id
        var meRequest = URLRequest(url: url)
        meRequest.httpMethod = "POST"
        meRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        meRequest.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        meRequest.httpBody = "{ \"query\": \"{ me { id } }\" }".data(using: .utf8)
        
        var userId: Int?
        do {
            let (data, _) = try await URLSession.shared.data(for: meRequest)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let meArr = dataDict["me"] as? [[String: Any]],
               let me = meArr.first,
               let uid = me["id"] as? Int {
                userId = uid
            }
        } catch {
            return []
        }
        guard let uid = userId else { return [] }
        
        // Step 2: query finished user_books for the provided book ids (chunked)
        let chunkSize = 50
        var finishedSet = Set<Int>()
        
        for chunkStart in stride(from: 0, to: bookIds.count, by: chunkSize) {
            let chunk = Array(bookIds[chunkStart..<min(chunkStart + chunkSize, bookIds.count)])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            
            let query = """
            query ($userId: Int!, $ids: [Int!]) {
              user_books(
                where: {
                  user_id: { _eq: $userId },
                  status_id: { _eq: 3 },
                  book_id: { _in: $ids }
                }
              ) {
                book_id
              }
            }
            """
            let body: [String: Any] = [
                "query": query,
                "variables": ["userId": uid, "ids": chunk]
            ]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, _) = try await URLSession.shared.data(for: request)
                if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errs = root["errors"] as? [[String: Any]],
                   !errs.isEmpty {
                    continue
                }
                if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataDict = root["data"] as? [String: Any],
                   let rows = dataDict["user_books"] as? [[String: Any]] {
                    for row in rows {
                        if let bid = row["book_id"] as? Int {
                            finishedSet.insert(bid)
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        return Array(finishedSet)
    }
    
    // Returns a dictionary mapping book IDs to their most recent read dates for finished books
    func fetchFinishedBooksWithDates(for bookIds: [Int]) async -> [Int: Date] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [:] }
        guard !bookIds.isEmpty else { return [:] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [:] }
        
        // Step 1: fetch current user's id
        var meRequest = URLRequest(url: url)
        meRequest.httpMethod = "POST"
        meRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        meRequest.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        meRequest.httpBody = "{ \"query\": \"{ me { id } }\" }".data(using: .utf8)
        
        var userId: Int?
        do {
            let (data, _) = try await URLSession.shared.data(for: meRequest)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let meArr = dataDict["me"] as? [[String: Any]],
               let me = meArr.first,
               let uid = me["id"] as? Int {
                userId = uid
            }
        } catch {
            return [:]
        }
        guard let uid = userId else { return [:] }
        
        // Prepare robust date parsers:
        // 1) "yyyy-MM-dd" (what your response shows)
        // 2) ISO8601 with fractional seconds
        // 3) ISO8601 without fractional seconds
        // 4) ISO8601 full date (also handles "yyyy-MM-dd")
        let ymdFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        let isoDateOnly = ISO8601DateFormatter()
        isoDateOnly.formatOptions = [.withFullDate]
        
        func parseFinishedAt(_ s: String) -> Date? {
            if let d = ymdFormatter.date(from: s) { return d }
            if let d = isoFrac.date(from: s) { return d }
            if let d = isoBasic.date(from: s) { return d }
            if let d = isoDateOnly.date(from: s) { return d }
            return nil
        }
        
        // Step 2: query finished user_books with their most recent finished_at dates
        let chunkSize = 50
        var finishedDatesDict: [Int: Date] = [:]
        
        for chunkStart in stride(from: 0, to: bookIds.count, by: chunkSize) {
            let chunk = Array(bookIds[chunkStart..<min(chunkStart + chunkSize, bookIds.count)])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            
            let query = """
            query ($userId: Int!, $ids: [Int!]) {
              user_books(
                where: {
                  user_id: { _eq: $userId },
                  status_id: { _eq: 3 },
                  book_id: { _in: $ids }
                }
              ) {
                book_id
                user_book_reads(
                  where: { finished_at: { _is_null: false } },
                  order_by: { finished_at: desc },
                  limit: 1
                ) {
                  finished_at
                }
              }
            }
            """
            let body: [String: Any] = [
                "query": query,
                "variables": ["userId": uid, "ids": chunk]
            ]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, _) = try await URLSession.shared.data(for: request)
                if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errs = root["errors"] as? [[String: Any]],
                   !errs.isEmpty {
                    continue
                }
                if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataDict = root["data"] as? [String: Any],
                   let rows = dataDict["user_books"] as? [[String: Any]] {
                    for row in rows {
                        if let bookId = row["book_id"] as? Int,
                           let reads = row["user_book_reads"] as? [[String: Any]],
                           let firstRead = reads.first,
                           let finishedAtStr = firstRead["finished_at"] as? String,
                           let finishedDate = parseFinishedAt(finishedAtStr) {
                            finishedDatesDict[bookId] = finishedDate
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        return finishedDatesDict
    }
}
