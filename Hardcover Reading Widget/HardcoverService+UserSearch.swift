import Foundation

extension HardcoverService {
    static func searchUsers(query: String) async -> [UserSearchResult] {
        print("🔍 searchUsers called with query: '\(query)'")
        
        guard !query.isEmpty else {
            print("❌ Empty query")
            return []
        }
        
        guard let url = URL(string: "https://search.hardcover.app/multi_search?x-typesense-api-key=7JRcb63AvYIo2WJvE3IzH4f8j1z9fHcC") else {
            print("❌ Invalid URL")
            return []
        }
        
        print("📡 Sending request to Typesense...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        
        let searchBody: [String: Any] = [
            "searches": [
                [
                    "per_page": 30,
                    "prioritize_exact_match": true,
                    "num_typos": 5,
                    "prioritize_num_matching_fields": false,
                    "text_match_type": "max_weight",
                    "query_by": "name,username,location",
                    "sort_by": "_text_match:desc,followers_count:desc",
                    "query_by_weights": "2,2,1",
                    "collection": "User_production",
                    "q": query,
                    "page": 1
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: searchBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Response status: \(httpResponse.statusCode)")
                guard httpResponse.statusCode == 200 else {
                    print("❌ Non-200 status")
                    return []
                }
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let firstResult = results.first,
                  let hits = firstResult["hits"] as? [[String: Any]] else {
                print("❌ Could not parse response")
                if let responseStr = String(data: data, encoding: .utf8) {
                    print("Response: \(responseStr.prefix(300))")
                }
                return []
            }
            
            print("✅ Found \(hits.count) hits")
            
            var users: [UserSearchResult] = []
            
            for (index, hit) in hits.enumerated() {
                guard let document = hit["document"] as? [String: Any] else {
                    print("⚠️ Hit \(index) has no document")
                    continue
                }
                
                if index == 0 {
                    print("🔑 First document keys: \(document.keys.joined(separator: ", "))")
                }
                
                // Try to get id as Int or String
                var id: Int?
                if let idInt = document["id"] as? Int {
                    id = idInt
                } else if let idString = document["id"] as? String, let idInt = Int(idString) {
                    id = idInt
                }
                
                guard let userId = id else {
                    print("⚠️ Hit \(index) missing id, value: \(String(describing: document["id"]))")
                    continue
                }
                
                guard let username = document["username"] as? String else {
                    print("⚠️ Hit \(index) (id: \(userId)) missing username")
                    continue
                }
                
                let name = document["name"] as? String
                let bio = document["bio"] as? String
                
                // Handle image as dictionary
                var imageUrl: String?
                if let imageDict = document["image"] as? [String: Any],
                   let url = imageDict["url"] as? String {
                    imageUrl = url
                } else if let imageString = document["image"] as? String {
                    imageUrl = imageString
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
            print("❌ Error: \(error)")
            return []
        }
    }
}
