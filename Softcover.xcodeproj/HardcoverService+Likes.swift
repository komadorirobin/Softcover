import Foundation

extension HardcoverService {
    // Explicit UNLIKE via Hasura delete on likes table, then confirm via fetchLikesBatch
    static func deleteLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let userId = await fetchUserId(apiKey: HardcoverConfig.apiKey) else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        // Hasura-style delete by composite predicate
        let mutation = """
        mutation ($likeableId: Int!, $likeableType: String!, $userId: Int!) {
          delete_likes(
            where: {
              likeable_id: { _eq: $likeableId },
              likeable_type: { _eq: $likeableType },
              user_id: { _eq: $userId }
            }
          ) {
            affected_rows
          }
        }
        """
        let vars: [String: Any] = [
            "likeableId": likeableId,
            "likeableType": likeableType,
            "userId": userId
        ]
        let body: [String: Any] = ["query": mutation, "variables": vars]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)

            // If GraphQL returns errors, treat as failure
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = root["errors"] as? [[String: Any]],
               !errors.isEmpty {
                return nil
            }

            // Small delay to avoid eventual consistency in the follow-up confirmation
            try? await Task.sleep(nanoseconds: 200_000_000)

            // Confirm the status and count from source of truth
            let confirmed = await fetchLikesBatch(for: [likeableId])
            if let v = confirmed[likeableId] {
                return (v.count, v.mine)
            }
            return nil
        } catch {
            return nil
        }
    }
}
