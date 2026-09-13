import Foundation

// MARK: - Prompt Models
struct PromptAnswer: Codable, Identifiable, Equatable {
    let id: Int
    let createdAt: String
    let promptId: Int
    let userId: Int
    let prompt: Prompt
    var previewBooks: [PromptBook]? // Not from API, populated separately
    
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case promptId = "prompt_id"
        case userId = "user_id"
        case prompt
    }
    
    static func == (lhs: PromptAnswer, rhs: PromptAnswer) -> Bool {
        return lhs.id == rhs.id
    }
}

struct Prompt: Codable, Equatable {
    let id: Int
    let slug: String
    let question: String?
    let description: String?
}

// MARK: - Prompt Answer Details
struct PromptAnswerBookEntry: Codable, Identifiable {
    let id: Int
    let position: Int?
    let promptAnswerId: Int
    let promptAnswer: PromptAnswerInfo
    let book: PromptBook
    
    enum CodingKeys: String, CodingKey {
        case id
        case position
        case promptAnswerId = "prompt_answer_id"
        case promptAnswer = "prompt_answer"
        case book
    }
}

struct PromptAnswerInfo: Codable {
    let id: Int
    let user: PromptUser
}

struct UserPromptAnswer: Identifiable {
    let id: Int
    let user: PromptUser
    let books: [PromptBook]
}

struct PromptUser: Codable, Equatable {
    let username: String
    let image: UserImage?
}

struct UserImage: Codable, Equatable {
    let url: String?
}

struct PromptBook: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let image: String?
    let cachedImage: CachedPromptImage?
    let description: String? // User's answer for why they chose this book
    
    enum CodingKeys: String, CodingKey {
        case id, title, image, description
        case cachedImage = "cached_image"
    }
    
    static func == (lhs: PromptBook, rhs: PromptBook) -> Bool {
        return lhs.id == rhs.id
    }
}

struct CachedPromptImage: Codable, Equatable {
    let url: String?
}

extension HardcoverService {
    /// Fetch answered prompts for the current user with progressive loading
    static func fetchAnsweredPrompts(onPromptLoaded: @escaping @MainActor (PromptAnswer) -> Void) async -> [PromptAnswer] {
        guard let profile = await fetchUserProfile() else {
            print("❌ Could not fetch user profile")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        return await fetchAnsweredPrompts(forUserId: profile.id, onPromptLoaded: onPromptLoaded)
    }
    
    /// Fetch answered prompts for the current user (without progressive loading)
    static func fetchAnsweredPrompts() async -> [PromptAnswer] {
        guard let profile = await fetchUserProfile() else {
            print("❌ Could not fetch user profile")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        return await fetchAnsweredPrompts(forUserId: profile.id, onPromptLoaded: { _ in })
    }
    
    /// Fetch answered prompts for a specific user by username with progressive loading
    static func fetchAnsweredPrompts(forUsername username: String, onPromptLoaded: @escaping @MainActor (PromptAnswer) -> Void) async -> [PromptAnswer] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key available")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid API URL")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Query prompt_answers with nested user.username filter
        let query = """
        query {
          prompt_answers(
            where: {user: {username: {_eq: "\(username)"}}}, 
            order_by: {created_at: desc}
          ) {
            id
            created_at
            prompt_id
            user_id
            prompt {
              id
              slug
              question
              description
            }
          }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            print("❌ Failed to serialize request body")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        
        req.httpBody = httpBody
        
        do {
            let (data, response) = try await HardcoverHTTP.shared.data(for: req)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Prompts HTTP Status: \(httpResponse.statusCode)")
            }
            
            if let raw = String(data: data, encoding: .utf8) {
                print("📥 Prompts Response (first 500 chars): \(raw.prefix(500))")
            }
            
            // Parse the response
            let decoder = JSONDecoder()
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let promptAnswers = dataDict["prompt_answers"] as? [[String: Any]] {
                
                // Convert back to data and decode
                let answersData = try JSONSerialization.data(withJSONObject: promptAnswers)
                let answers = try decoder.decode([PromptAnswer].self, from: answersData)
                
                // Remove duplicates based on promptId
                var uniqueAnswers: [PromptAnswer] = []
                var seenPromptIds = Set<Int>()
                
                for answer in answers {
                    if !seenPromptIds.contains(answer.promptId) {
                        uniqueAnswers.append(answer)
                        seenPromptIds.insert(answer.promptId)
                    }
                }
                
                print("✅ Fetched \(uniqueAnswers.count) unique prompt answers for @\(username)")
                
                // Return prompts immediately without preview books
                for answer in uniqueAnswers {
                    guard !Task.isCancelled else { return [] }
                    await MainActor.run {
                        onPromptLoaded(answer)
                    }
                }
                
                // Fetch preview books for each prompt asynchronously
                await withTaskGroup(of: (Int, [PromptBook]?).self) { group in
                    for (index, answer) in uniqueAnswers.enumerated() {
                        if Task.isCancelled { group.cancelAll(); break }
                        group.addTask {
                            let userAnswers = await fetchPromptAnswers(
                                promptId: answer.promptId,
                                userId: answer.userId,
                                username: username,
                                slug: answer.prompt.slug
                            )
                            return (index, userAnswers.first?.books)
                        }
                    }
                    
                    for await (index, books) in group {
                        if Task.isCancelled { group.cancelAll(); break }
                        if let books = books {
                            uniqueAnswers[index].previewBooks = books
                            let updatedAnswer = uniqueAnswers[index]
                            await MainActor.run {
                                onPromptLoaded(updatedAnswer)
                            }
                        }
                    }
                }
                
                return uniqueAnswers
            } else {
                print("❌ Could not parse GraphQL response")
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
        } catch {
            HardcoverReadScope.failure?.record(error)
            print("❌ Error fetching prompts: \(error)")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
    }
    
    /// Fetch answered prompts for a specific user by username (without progressive loading)
    static func fetchAnsweredPrompts(forUsername username: String) async -> [PromptAnswer] {
        return await fetchAnsweredPrompts(forUsername: username, onPromptLoaded: { _ in })
    }
    
    /// Fetch answered prompts for a specific user ID (old GraphQL method, kept for current user)
    private static func fetchAnsweredPrompts(forUserId userId: Int, onPromptLoaded: @escaping @MainActor (PromptAnswer) -> Void) async -> [PromptAnswer] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key available")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid API URL")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query {
          prompt_answers(where: {user_id: {_eq: \(userId)}}, order_by: {created_at: desc}) {
            id
            created_at
            prompt_id
            user_id
            prompt {
              id
              slug
              question
              description
            }
          }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            print("❌ Failed to serialize request body")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        
        req.httpBody = httpBody
        
        do {
            let (data, response) = try await HardcoverHTTP.shared.data(for: req)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Prompts HTTP Status: \(httpResponse.statusCode)")
            }
            
            if let raw = String(data: data, encoding: .utf8) {
                print("📥 Prompts Raw Response: \(raw)")
            }
            
            // Parse the response
            let decoder = JSONDecoder()
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let promptAnswers = dataDict["prompt_answers"] as? [[String: Any]] {
                
                // Convert back to data and decode
                let answersData = try JSONSerialization.data(withJSONObject: promptAnswers)
                let answers = try decoder.decode([PromptAnswer].self, from: answersData)
                
                // Remove duplicates based on promptId (database may return one row per book)
                var uniqueAnswers: [PromptAnswer] = []
                var seenPromptIds = Set<Int>()
                
                for answer in answers {
                    if !seenPromptIds.contains(answer.promptId) {
                        uniqueAnswers.append(answer)
                        seenPromptIds.insert(answer.promptId)
                    }
                }
                
                // Return prompts immediately without preview books
                for answer in uniqueAnswers {
                    guard !Task.isCancelled else { return [] }
                    await MainActor.run {
                        onPromptLoaded(answer)
                    }
                }
                
                // Get username for loading books
                guard let username = await fetchUsername(forUserId: userId) else {
                    print("✅ Fetched \(uniqueAnswers.count) unique prompt answers (from \(answers.count) total rows) - no username for books")
                    return uniqueAnswers
                }
                
                // Fetch preview books for each prompt asynchronously
                await withTaskGroup(of: (Int, [PromptBook]?).self) { group in
                    for (index, answer) in uniqueAnswers.enumerated() {
                        if Task.isCancelled { group.cancelAll(); break }
                        group.addTask {
                            let userAnswers = await fetchPromptAnswers(
                                promptId: answer.promptId,
                                userId: answer.userId,
                                username: username,
                                slug: answer.prompt.slug
                            )
                            return (index, userAnswers.first?.books)
                        }
                    }
                    
                    for await (index, books) in group {
                        if Task.isCancelled { group.cancelAll(); break }
                        if let books = books {
                            uniqueAnswers[index].previewBooks = books
                            let updatedAnswer = uniqueAnswers[index]
                            await MainActor.run {
                                onPromptLoaded(updatedAnswer)
                            }
                        }
                    }
                }
                
                print("✅ Fetched \(uniqueAnswers.count) unique prompt answers (from \(answers.count) total rows)")
                return uniqueAnswers
            }
            
            print("⚠️ No prompt answers found in response")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
            
        } catch {
            HardcoverReadScope.failure?.record(error)
            print("❌ Error fetching prompts: \(error)")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
    }
    
    /// Fetch username for a given user ID
    static func fetchUsername(forUserId userId: Int) async -> String? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            return nil
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query {
          users(where: {id: {_eq: \(userId)}}, limit: 1) {
            username
          }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }
        
        req.httpBody = httpBody
        
        do {
            let (data, _) = try await HardcoverHTTP.shared.data(for: req)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let users = dataDict["users"] as? [[String: Any]],
               let firstUser = users.first,
               let username = firstUser["username"] as? String {
                return username
            }
        } catch {
            print("❌ Error fetching username: \(error)")
        }
        
        return nil
    }
    
    /// Fetch a specific user's answer for a specific prompt
    static func fetchPromptAnswers(promptId: Int, userId: Int, username: String, slug: String) async -> [UserPromptAnswer] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key available")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        
        guard let url = URL(string: "https://hardcover.app/@\(username)/prompts/\(slug)") else {
            print("❌ Invalid URL")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await HardcoverHTTP.shared.data(for: req)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 HTML Response Status: \(httpResponse.statusCode)")
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ Could not decode HTML")
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
            // Extract JSON from data-page attribute
            guard let dataPageStart = html.range(of: "data-page=\"{") else {
                print("❌ Could not find data-page attribute")
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
            let jsonStart = html.index(dataPageStart.lowerBound, offsetBy: 11) // Skip 'data-page="'
            
            // Find matching closing brace by counting depth
            var depth = 0
            var jsonEnd: String.Index? = nil
            var i = jsonStart
            
            while i < html.endIndex {
                let char = html[i]
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        jsonEnd = html.index(after: i)
                        break
                    }
                } else if char == "\"" && i == jsonStart {
                    // Skip the opening quote of the data-page attribute
                    i = html.index(after: i)
                    continue
                }
                i = html.index(after: i)
            }
            
            guard let jsonEnd = jsonEnd else {
                print("❌ Could not find matching closing brace")
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
            let jsonString = String(html[jsonStart..<jsonEnd])
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
            
            print("📦 Extracted JSON length: \(jsonString.count)")
            
            guard let jsonData = jsonString.data(using: .utf8) else {
                print("❌ Could not convert to data")
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
            guard let pageData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("❌ Invalid JSON - first 500 chars:")
                if jsonString.count > 500 {
                    print(String(jsonString.prefix(500)))
                } else {
                    print(jsonString)
                }
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
            print("📦 Page data keys: \(pageData.keys.joined(separator: ", "))")
            
            guard let props = pageData["props"] as? [String: Any] else {
                print("❌ No props found")
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
            print("📦 Props keys: \(props.keys.joined(separator: ", "))")
            
            guard let prompt = props["prompt"] as? [String: Any] else {
                print("❌ No prompt found")
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
            print("📦 Prompt keys: \(prompt.keys.joined(separator: ", "))")
            
            guard let promptBooks = prompt["promptBooks"] as? [[String: Any]] else {
                print("❌ No promptBooks found")
                HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
                return []
            }
            
            print("✅ Found \(promptBooks.count) prompt books")
            
            // Parse books
            var books: [PromptBook] = []
            for promptBook in promptBooks {
                guard let bookDict = promptBook["book"] as? [String: Any],
                      let id = bookDict["id"] as? Int,
                      let title = bookDict["title"] as? String else {
                    continue
                }
                
                // Parse image - can be either a string URL or an object with url property
                var imageUrl: String? = nil
                if let imageStr = bookDict["image"] as? String {
                    imageUrl = imageStr
                } else if let imageDict = bookDict["image"] as? [String: Any],
                          let url = imageDict["url"] as? String {
                    imageUrl = url
                }
                
                let cachedImageUrl = (bookDict["cached_image"] as? [String: Any])?["url"] as? String
                let cachedImage = cachedImageUrl != nil ? CachedPromptImage(url: cachedImageUrl) : nil
                
                // Get the user's description/answer for this book
                let description = promptBook["description"] as? String
                
                books.append(PromptBook(id: id, title: title, image: imageUrl, cachedImage: cachedImage, description: description))
            }
            
            // Create a single answer with the user and their books
            // Fetch user image from profile
            var userImage: UserImage? = nil
            if let userProfile = await fetchUserProfile(username: username) {
                userImage = userProfile.image != nil ? UserImage(url: userProfile.image?.url) : nil
            }
            
            let user = PromptUser(username: username, image: userImage)
            let answer = UserPromptAnswer(id: promptId, user: user, books: books)
            
            print("✅ Fetched \(books.count) books from HTML")
            return [answer]
            
        } catch {
            HardcoverReadScope.failure?.record(error)
            print("❌ Error fetching prompt HTML: \(error)")
            HardcoverReadScope.failure?.record(HardcoverNetworkError.invalidResponse)
            return []
        }
    }
}
