import Foundation

extension HardcoverService {
    static func searchUsers(query: String) async -> [UserSearchResult] {
        print("🔍 searchUsers called with query: '\(query)'")
        
        guard !query.isEmpty else {
            print("❌ Empty query")
            return []
        }
        
        // Use Typesense multi_search endpoint
        let searchRequest: [String: Any] = [
            "searches": [
                [
                    "collection": "User_production",
                    "q": query,
                    "query_by": "name,username,location",
                    "query_by_weights": "2,2,1",
                    "per_page": 30,
                    "prioritize_exact_match": true,
                    "num_typos": 5,
                    "prioritize_num_matching_fields": false,
                    "text_match_type": "max_weight",
                    "sort_by": "_text_match:desc,followers_count:desc",
                    "page": 1
                ]
            ]
        ]
        
        guard let url = URL(string: "https://production-search.hardcover.app/multi_search?x-typesense-api-key=6fVaVYkPPPBurjELLAmzIj8gBG1FnClB"),
              let jsonData = try? JSONSerialization.data(withJSONObject: searchRequest) else {
            print("❌ Failed to create request")
            return []
        }
        
        print("📡 Sending Typesense multi_search request...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Response status: \(httpResponse.statusCode)")
                
                guard httpResponse.statusCode == 200 else {
                    print("❌ Non-200 status")
                    if let responseStr = String(data: data, encoding: .utf8) {
                        print("Response: \(responseStr.prefix(500))")
                    }
                    return []
                }
            }
            
            return parseTypesenseResponse(data)
            
        } catch {
            print("❌ Error: \(error)")
            return []
        }
    }
    
    private static func parseTypesenseResponse(_ data: Data) -> [UserSearchResult] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Could not parse JSON")
                return []
            }
            
            // Debug: print the entire response structure
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 Full response: \(jsonString.prefix(1000))")
            }
            
            guard let results = json["results"] as? [[String: Any]],
                  let firstResult = results.first,
                  let hits = firstResult["hits"] as? [[String: Any]] else {
                print("❌ Could not find hits in response")
                print("📦 JSON keys: \(json.keys)")
                if let results = json["results"] as? [[String: Any]] {
                    print("📦 Results count: \(results.count)")
                    if let firstResult = results.first {
                        print("📦 First result keys: \(firstResult.keys)")
                    }
                }
                return []
            }
            
            print("✅ Found \(hits.count) users from Typesense")
            
            var users: [UserSearchResult] = []
            
            for hit in hits {
                guard let document = hit["document"] as? [String: Any] else {
                    continue
                }
                
                // ID can be either Int or String
                let userId: Int
                if let idInt = document["id"] as? Int {
                    userId = idInt
                } else if let idString = document["id"] as? String, let idInt = Int(idString) {
                    userId = idInt
                } else {
                    print("⚠️ Could not parse user ID")
                    continue
                }
                
                guard let username = document["username"] as? String else {
                    print("⚠️ User \(userId) missing username")
                    continue
                }
                
                let name = document["name"] as? String
                let bio = document["bio"] as? String
                
                // Handle image as dictionary
                var imageUrl: String?
                if let imageDict = document["image"] as? [String: Any],
                   let url = imageDict["url"] as? String {
                    imageUrl = url
                }
                
                let user = UserSearchResult(
                    id: userId,
                    username: username,
                    name: name,
                    image: imageUrl,
                    bio: bio
                )
                
                users.append(user)
            }
            
            print("✅ Returning \(users.count) users")
            return users
            
        } catch {
            print("❌ JSON parsing error: \(error)")
            return []
        }
    }
    
    // Fallback: GraphQL query
    private static func searchUsersFallback(query: String) async -> [UserSearchResult] {
        let graphqlQuery = """
        query {
          users(limit: 100, order_by: {username: asc}) {
            id
            username
            name
            bio
            image {
              url
            }
          }
        }
        """
        
        let requestBody: [String: Any] = ["query": graphqlQuery]
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql"),
              let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to create request")
            return []
        }
        
        print("📡 Sending GraphQL request...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Response status: \(httpResponse.statusCode)")
                guard httpResponse.statusCode == 200 else {
                    print("❌ Non-200 status")
                    if let responseStr = String(data: data, encoding: .utf8) {
                        print("Response: \(responseStr.prefix(500))")
                    }
                    return []
                }
            }
            
            return parseAndFilterUsers(data, query: query)
            
        } catch {
            print("❌ Error: \(error)")
            return []
        }
    }
    
    private static func parseAndFilterUsers(_ data: Data, query: String) -> [UserSearchResult] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Could not parse JSON")
                return []
            }
            
            // Check for errors
            if let errors = json["errors"] as? [[String: Any]] {
                print("❌ GraphQL errors:")
                for error in errors {
                    if let message = error["message"] as? String {
                        print("  - \(message)")
                    }
                }
                return []
            }
            
            guard let dataDict = json["data"] as? [String: Any],
                  let usersArray = dataDict["users"] as? [[String: Any]] else {
                print("❌ Could not find users in response")
                return []
            }
            
            print("✅ Fetched \(usersArray.count) users from API")
            
            if usersArray.count == 100 {
                print("⚠️ API returned exactly 100 users - may be hitting server limit")
            }
            
            // Filter and score users client-side by username or name
            let lowercaseQuery = query.lowercased()
            
            struct ScoredUser {
                let userDict: [String: Any]
                let score: Int
            }
            
            let scoredUsers = usersArray.compactMap { userDict -> ScoredUser? in
                let username = (userDict["username"] as? String ?? "").lowercased()
                let name = (userDict["name"] as? String ?? "").lowercased()
                
                // Score users based on match quality
                var score = 0
                
                // Exact username match = highest priority
                if username == lowercaseQuery {
                    score = 1000
                }
                // Username starts with query = high priority
                else if username.hasPrefix(lowercaseQuery) {
                    score = 500
                }
                // Username contains query
                else if username.contains(lowercaseQuery) {
                    score = 100
                }
                // Exact name match
                else if name == lowercaseQuery {
                    score = 400
                }
                // Name starts with query
                else if name.hasPrefix(lowercaseQuery) {
                    score = 200
                }
                // Name contains query
                else if name.contains(lowercaseQuery) {
                    score = 50
                }
                
                if score > 0 {
                    return ScoredUser(userDict: userDict, score: score)
                }
                return nil
            }
            
            // Sort by score (highest first) and take top 20
            let filteredUsers = scoredUsers
                .sorted { $0.score > $1.score }
                .prefix(20)
                .map { $0.userDict }
            
            print("✅ Filtered to \(filteredUsers.count) matching users")
            
            var users: [UserSearchResult] = []
            
            for (index, userDict) in filteredUsers.enumerated() {
                guard let userId = userDict["id"] as? Int else {
                    print("⚠️ User \(index) missing id")
                    continue
                }
                
                guard let username = userDict["username"] as? String else {
                    print("⚠️ User \(index) (id: \(userId)) missing username")
                    continue
                }
                
                let name = userDict["name"] as? String
                let bio = userDict["bio"] as? String
                
                // Handle image as dictionary
                var imageUrl: String?
                if let imageDict = userDict["image"] as? [String: Any],
                   let url = imageDict["url"] as? String {
                    imageUrl = url
                }
                
                let user = UserSearchResult(
                    id: userId,
                    username: username,
                    name: name,
                    image: imageUrl,
                    bio: bio
                )
                
                users.append(user)
            }
            
            print("✅ Returning \(users.count) users")
            return users
            
        } catch {
            print("❌ JSON parsing error: \(error)")
            return []
        }
    }
}
