import Foundation

extension HardcoverService {
    /// Follow a user by user ID (preferred method)
    static func followUserById(userId: Int) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key configured")
            return false
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid URL")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let mutation = """
        mutation CreateFollowedUser($userId: Int!) {
          insertResponse: insert_followed_user(user_id: $userId) {
            error
            followed_users {
              userId: user_id
              followedUserId: followed_user_id
            }
          }
        }
        """
        
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["userId": userId]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Follow response status: \(httpResponse.statusCode)")
            }
            
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 Follow response: \(String(jsonString.prefix(300)))")
            }
            
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = jsonObject["errors"] as? [[String: Any]], !errors.isEmpty {
                    print("❌ Follow errors: \(errors)")
                    return false
                }
                
                if let data = jsonObject["data"] as? [String: Any],
                   let insertResult = data["insertResponse"] as? [String: Any] {
                    
                    // Check for error field
                    if let error = insertResult["error"] as? String, !error.isEmpty {
                        print("❌ Follow error: \(error)")
                        return false
                    }
                    
                    // Check if followed_users exists (it's an object, not array!)
                    if let followedUser = insertResult["followed_users"] as? [String: Any] {
                        print("✅ Successfully followed user ID \(userId)")
                        return true
                    }
                }
            }
            
            print("⚠️ Unexpected follow response")
            return false
        } catch {
            print("❌ Follow request failed: \(error)")
            return false
        }
    }
    
    /// Unfollow a user by user ID (preferred method)
    static func unfollowUserById(userId: Int) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key configured")
            return false
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid URL")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let mutation = """
        mutation DeleteFollowedUser($userId: Int!) {
          deleteResponse: delete_followed_user(user_id: $userId) {
            id
            userId: user_id
            followedUserId: followed_user_id
          }
        }
        """
        
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["userId": userId]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Unfollow response status: \(httpResponse.statusCode)")
            }
            
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 Unfollow response: \(String(jsonString.prefix(300)))")
            }
            
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = jsonObject["errors"] as? [[String: Any]], !errors.isEmpty {
                    print("❌ Unfollow errors: \(errors)")
                    return false
                }
                
                if let data = jsonObject["data"] as? [String: Any],
                   let deleteResult = data["deleteResponse"] as? [String: Any],
                   deleteResult["id"] != nil {
                    print("✅ Successfully unfollowed user ID \(userId)")
                    return true
                }
            }
            
            print("⚠️ Unexpected unfollow response")
            return false
        } catch {
            print("❌ Unfollow request failed: \(error)")
            return false
        }
    }
    
    /// Follow a user by username
    static func followUser(username: String) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key configured")
            return false
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid URL")
            return false
        }
        
        // First, get the user's ID
        guard let userId = await getUserId(username: username) else {
            print("❌ Could not find user ID for @\(username)")
            return false
        }
        
        // Use the userId version
        return await followUserById(userId: userId)
    }
    
    /// Unfollow a user by username
    static func unfollowUser(username: String) async -> Bool {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key configured")
            return false
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid URL")
            return false
        }
        
        // First, get the user's ID
        guard let userId = await getUserId(username: username) else {
            print("❌ Could not find user ID for @\(username)")
            return false
        }
        
        // Use the userId version
        return await unfollowUserById(userId: userId)
    }
    
    /// Get user ID from username
    private static func getUserId(username: String) async -> Int? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Use case-insensitive matching
        let query = """
        query GetUserId($username: String!) {
          users(where: { username: { _ilike: $username } }, limit: 1) {
            id
            username
          }
        }
        """
        
        let body: [String: Any] = [
            "query": query,
            "variables": ["username": username]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let jsonString = String(data: data, encoding: .utf8) {
                print("🔍 getUserId response: \(String(jsonString.prefix(500)))")
            }
            
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errors = jsonObject["errors"] as? [[String: Any]], !errors.isEmpty {
                    print("❌ getUserId errors: \(errors)")
                }
                
                if let dataDict = jsonObject["data"] as? [String: Any],
                   let users = dataDict["users"] as? [[String: Any]],
                   let firstUser = users.first,
                   let userId = firstUser["id"] as? Int {
                    print("✅ Found user ID \(userId) for @\(username)")
                    return userId
                }
            }
        } catch {
            print("❌ Failed to get user ID: \(error)")
        }
        
        print("❌ No user found with username: \(username)")
        return nil
    }
}
