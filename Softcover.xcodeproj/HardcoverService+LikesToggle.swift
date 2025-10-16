import Foundation

extension HardcoverService {
    // Public helper: set like state explicitly. When like == true -> ensure like exists; when false -> remove like.
    static func setLike(likeableId: Int, like: Bool, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        if like {
            return await upsertLike(likeableId: likeableId, likeableType: likeableType)
        } else {
            return await deleteLike(likeableId: likeableId, likeableType: likeableType)
        }
    }
    
    // Ensure current user's like exists for a given likeable. Returns latest (count, didLike) after upsert.
    static func upsertLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        print("🔄 UpsertLike starting - likeableId: \(likeableId), type: \(likeableType)")
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Use Hardcover's custom upsert_like mutation (mirrors their web client)
        let mutation = """
        mutation UpsertLike($likeableId: Int!, $likeableType: String!) {
          likeResult: upsert_like(likeable_id: $likeableId, likeable_type: $likeableType) {
            likesCount: likes_count
            __typename
          }
        }
        """
        let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Log raw response for debugging
            if let responseStr = String(data: data, encoding: .utf8) {
                print("🔍 UpsertLike response: \(responseStr)")
            }
            
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ UpsertLike failed - invalid JSON")
                return nil
            }
            
            // Check for GraphQL errors
            if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
                print("❌ UpsertLike GraphQL errors: \(errors)")
                return nil
            }
            
            guard let dataDict = root["data"] as? [String: Any],
                  let likeResult = dataDict["likeResult"] as? [String: Any],
                  let likesCount = likeResult["likesCount"] as? Int else {
                print("❌ UpsertLike failed - invalid response structure")
                print("   Full response: \(root)")
                return nil
            }
            
            // The upsert_like mutation ensures our like exists; didLike should be true after success.
            print("✅ UpsertLike successful - likesCount: \(likesCount)")
            return (max(0, likesCount), true)
        } catch {
            print("❌ UpsertLike exception: \(error)")
            return nil
        }
    }
    
    // Remove current user's like for a given likeable. Returns latest (count, didLike) after deletion.
    static func deleteLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        print("🔄 DeleteLike starting - likeableId: \(likeableId), type: \(likeableType)")
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // Use Hardcover's custom delete_like mutation (matches their web interface)
        let mutation = """
        mutation DeleteLike($likeableId: Int!, $likeableType: String!) {
          likeResult: delete_like(likeable_id: $likeableId, likeable_type: $likeableType) {
            likesCount: likes_count
            __typename
          }
        }
        """
        let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Log raw response for debugging
            if let responseStr = String(data: data, encoding: .utf8) {
                print("🔍 DeleteLike response: \(responseStr)")
            }
            
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ DeleteLike failed - invalid JSON")
                return nil
            }
            
            // Check for GraphQL errors
            if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
                print("❌ DeleteLike GraphQL errors: \(errors)")
                return nil
            }
            
            guard let dataDict = root["data"] as? [String: Any],
                  let likeResult = dataDict["likeResult"] as? [String: Any],
                  let likesCount = likeResult["likesCount"] as? Int else {
                print("❌ DeleteLike failed - invalid response structure")
                print("   Full response: \(root)")
                return nil
            }
            
            // The delete_like mutation returns the current count after deletion
            print("✅ DeleteLike successful - likesCount: \(likesCount)")
            return (max(0, likesCount), false) // false because we just deleted our like
        } catch {
            print("❌ DeleteLike exception: \(error)")
            return nil
        }
    }
    
    // Optional: confirm current count + whether current user has liked, if needed for debugging.
    private static func confirmLikeState(likeableId: Int, likeableType: String, userId: Int) async -> (likesCount: Int, didLike: Bool)? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($id: Int!, $type: String!, $userId: Int!) {
          likes(where: { likeable_id: { _eq: $id }, likeable_type: { _eq: $type } }) {
            likeable_id
          }
          myLikes: likes(where: { likeable_id: { _eq: $id }, likeable_type: { _eq: $type }, user_id: { _eq: $userId } }) {
            likeable_id
          }
        }
        """
        let vars: [String: Any] = ["id": likeableId, "type": likeableType, "userId": userId]
        let body: [String: Any] = ["query": query, "variables": vars]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["errors"] as? [[String: Any]])?.isEmpty != false,
                  let dataDict = root["data"] as? [String: Any] else {
                return nil
            }
            let all = (dataDict["likes"] as? [[String: Any]] ?? [])
            let my = (dataDict["myLikes"] as? [[String: Any]] ?? [])
            let count = all.count
            let mine = !my.isEmpty
            return (max(0, count), mine)
        } catch {
            return nil
        }
    }
    
    // Optional: fetch current user id (not used in the main path, but handy for confirmLikeState if ever needed)
    private static func fetchCurrentUserId() async -> Int? {
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
               let dataDict = root["data"] as? [String: Any],
               let meArr = dataDict["me"] as? [[String: Any]],
               let first = meArr.first,
               let id = first["id"] as? Int {
                return id
            }
        } catch {
            return nil
        }
        return nil
    }
}
