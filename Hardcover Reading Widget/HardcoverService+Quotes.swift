import Foundation

// MARK: - Quote Models

struct Quote: Identifiable, Codable {
    let id: Int
    let entry: String
    let bookId: Int
    let createdAt: String
    let bookTitle: String
    let authorName: String
    let editionId: Int?
    let privacySettingId: Int?
    let page: Int?
}

// MARK: - Quotes Extension

extension HardcoverService {

    // MARK: - Fetch all quotes for the current user

    static func fetchAllQuotes() async -> [Quote] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ fetchAllQuotes: No API key available")
            return []
        }

        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        // First get user ID
        let meQuery = """
        { "query": "{ me { id } }" }
        """
        request.httpBody = meQuery.data(using: .utf8)

        guard let userId: Int = await {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let me = dataObj["me"] as? [[String: Any]],
                   let first = me.first,
                   let id = first["id"] as? Int {
                    return id
                }
            } catch {
                print("❌ fetchAllQuotes: Failed to get user ID: \(error)")
            }
            return nil
        }() else { return [] }

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
            reading_journals(where: {event: {_eq: "quote"}}, order_by: {id: desc}) {
              id
              entry
              book_id
              created_at
              edition_id
              privacy_setting_id
              metadata
            }
          }
        }
        """

        let body: [String: Any] = ["query": query]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return [] }

        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("❌ fetchAllQuotes HTTP error: \(httpResponse.statusCode)")
                return []
            }


            // Debug: log raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 fetchAllQuotes response: \(responseString.prefix(500))")
            }

            if let jsonCheck = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = jsonCheck["errors"] as? [[String: Any]], !errors.isEmpty {
                print("❌ fetchAllQuotes errors: \(errors)")
                return []
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let userBooks = dataObj["user_books"] as? [[String: Any]] else {
                return []
            }

            var allQuotes: [Quote] = []

            for userBook in userBooks {
                guard let book = userBook["book"] as? [String: Any],
                      let bookTitle = book["title"] as? String,
                      let journals = userBook["reading_journals"] as? [[String: Any]] else {
                    continue
                }

                let contributions = book["contributions"] as? [[String: Any]] ?? []
                let authorName = contributions.compactMap { contrib -> String? in
                    (contrib["author"] as? [String: Any])?["name"] as? String
                }.joined(separator: ", ")

                let bookId = book["id"] as? Int ?? 0

                for journal in journals {
                    guard let journalId = journal["id"] as? Int,
                          let entry = journal["entry"] as? String else { continue }

                    let page = Self.extractPage(from: journal)
                    let quote = Quote(
                        id: journalId,
                        entry: entry,
                        bookId: journal["book_id"] as? Int ?? bookId,
                        createdAt: journal["created_at"] as? String ?? "",
                        bookTitle: bookTitle,
                        authorName: authorName.isEmpty ? "Unknown Author" : authorName,
                        editionId: journal["edition_id"] as? Int,
                        privacySettingId: journal["privacy_setting_id"] as? Int,
                        page: page
                    )
                    allQuotes.append(quote)
                }
            }

            print("[Quotes] Fetched \(allQuotes.count) quotes from \(userBooks.count) books")
            return allQuotes

        } catch {
            print("❌ fetchAllQuotes error: \(error)")
            return []
        }
    }

    // MARK: - Fetch quotes for a specific book

    static func fetchQuotesForBook(bookId: Int) async -> [Quote] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ fetchQuotesForBook: No API key available")
            return []
        }

        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        // First get user ID
        let meQuery = """
        { "query": "{ me { id } }" }
        """
        request.httpBody = meQuery.data(using: .utf8)

        guard let userId: Int = await {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let me = dataObj["me"] as? [[String: Any]],
                   let first = me.first,
                   let id = first["id"] as? Int {
                    return id
                }
            } catch {
                print("❌ fetchQuotesForBook: Failed to get user ID: \(error)")
            }
            return nil
        }() else { return [] }

        let query = """
        query {
          user_books(
            where: {
              user_id: {_eq: \(userId)},
              book_id: {_eq: \(bookId)},
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
            reading_journals(where: {event: {_eq: "quote"}}, order_by: {id: desc}) {
              id
              entry
              book_id
              created_at
              edition_id
              privacy_setting_id
              metadata
            }
          }
        }
        """

        let body: [String: Any] = ["query": query]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return [] }

        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("❌ fetchQuotesForBook HTTP error: \(httpResponse.statusCode)")
                return []
            }


            // Debug: log raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 fetchQuotesForBook response: \(responseString.prefix(500))")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }

            if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                print("❌ fetchQuotesForBook errors: \(errors)")
                return []
            }

            guard let dataObj = json["data"] as? [String: Any],
                  let userBooks = dataObj["user_books"] as? [[String: Any]] else {
                return []
            }

            var allQuotes: [Quote] = []

            for userBook in userBooks {
                guard let book = userBook["book"] as? [String: Any],
                      let bookTitle = book["title"] as? String,
                      let journals = userBook["reading_journals"] as? [[String: Any]] else {
                    continue
                }

                let contributions = book["contributions"] as? [[String: Any]] ?? []
                let authorName = contributions.compactMap { contrib -> String? in
                    (contrib["author"] as? [String: Any])?["name"] as? String
                }.joined(separator: ", ")

                for journal in journals {
                    guard let journalId = journal["id"] as? Int,
                          let entry = journal["entry"] as? String else { continue }

                    let page = Self.extractPage(from: journal)
                    let quote = Quote(
                        id: journalId,
                        entry: entry,
                        bookId: journal["book_id"] as? Int ?? bookId,
                        createdAt: journal["created_at"] as? String ?? "",
                        bookTitle: bookTitle,
                        authorName: authorName.isEmpty ? "Unknown Author" : authorName,
                        editionId: journal["edition_id"] as? Int,
                        privacySettingId: journal["privacy_setting_id"] as? Int,
                        page: page
                    )
                    allQuotes.append(quote)
                }
            }

            print("[Quotes] Fetched \(allQuotes.count) quotes for book \(bookId)")
            return allQuotes

        } catch {
            print("❌ fetchQuotesForBook error: \(error)")
            return []
        }
    }

    // MARK: - Create a new quote

    static func createQuote(bookId: Int, editionId: Int?, entry: String, page: Int? = nil, totalPages: Int? = nil, privacySettingId: Int = 1) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ createQuote: No API key available")
            return false
        }

        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        let mutation = """
        mutation InsertReadingJournalEntry($object: ReadingJournalCreateType!) {
          insert_reading_journal(object: $object) {
            reading_journal {
              id
            }
          }
        }
        """

        var object: [String: Any] = [
            "book_id": bookId,
            "event": "quote",
            "entry": entry,
            "privacy_setting_id": privacySettingId,
            "tags": [] as [[String: Any]]
        ]

        if let editionId = editionId {
            object["edition_id"] = editionId
        }

        // Page info goes in metadata.position (not as a top-level "page" field)
        if let page = page {
            var position: [String: Any] = [
                "type": "pages",
                "value": page
            ]
            if let totalPages = totalPages {
                position["possible"] = totalPages
            }
            object["metadata"] = ["position": position]
        }

        let body: [String: Any] = [
            "query": mutation,
            "variables": ["object": object]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = jsonData

        // Debug: log what we're sending
        if let bodyString = String(data: jsonData, encoding: .utf8) {
            print("📤 Create quote request body: \(bodyString.prefix(500))")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Create quote response status: \(httpResponse.statusCode)")
            }

            // Debug: log the full response
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Create quote response: \(responseString.prefix(500))")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                    print("❌ Create quote errors: \(errors)")
                    return false
                }

                if let dataObj = json["data"] as? [String: Any],
                   let insertResult = dataObj["insert_reading_journal"] as? [String: Any],
                   let journal = insertResult["reading_journal"] as? [String: Any],
                   let _ = journal["id"] as? Int {
                    print("✅ Quote created successfully")
                    return true
                }
            }

            return false

        } catch {
            print("❌ createQuote error: \(error)")
            return false
        }
    }

    // MARK: - Update an existing quote

    static func updateQuote(quoteId: Int, entry: String) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ updateQuote: No API key available")
            return false
        }

        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        let mutation = """
        mutation UpdateReadingJournal($id: Int!, $object: ReadingJournalUpdateType!) {
          update_reading_journal(id: $id, object: $object) {
            reading_journal {
              id
              entry
            }
          }
        }
        """

        let body: [String: Any] = [
            "query": mutation,
            "variables": [
                "id": quoteId,
                "object": ["entry": entry]
            ] as [String: Any]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Update quote response status: \(httpResponse.statusCode)")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                    print("❌ Update quote errors: \(errors)")
                    return false
                }

                if let dataObj = json["data"] as? [String: Any],
                   let _ = dataObj["update_reading_journal"] as? [String: Any] {
                    print("✅ Quote updated successfully")
                    return true
                }
            }

            return false

        } catch {
            print("❌ updateQuote error: \(error)")
            return false
        }
    }

    // MARK: - Delete a quote

    static func deleteQuote(quoteId: Int) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ deleteQuote: No API key available")
            return false
        }

        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        let mutation = """
        mutation DeleteReadingJournal($id: Int!) {
          delete_reading_journal(id: $id) {
            id
          }
        }
        """

        let body: [String: Any] = [
            "query": mutation,
            "variables": ["id": quoteId]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Delete quote response status: \(httpResponse.statusCode)")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                    print("❌ Delete quote errors: \(errors)")
                    return false
                }

                if let dataObj = json["data"] as? [String: Any],
                   let _ = dataObj["delete_reading_journal"] as? [String: Any] {
                    print("✅ Quote deleted successfully")
                    return true
                }
            }

            return false

        } catch {
            print("❌ deleteQuote error: \(error)")
            return false
        }
    }

    // MARK: - Helpers

    /// Extract page number from a reading journal's metadata.position.value
    private static func extractPage(from journal: [String: Any]) -> Int? {
        // Try direct "page" field first (in case the API supports it)
        if let page = journal["page"] as? Int {
            return page
        }
        // Then try metadata.position.value (the standard way)
        if let metadata = journal["metadata"] as? [String: Any],
           let position = metadata["position"] as? [String: Any],
           let value = position["value"] as? Int {
            return value
        }
        return nil
    }
}
