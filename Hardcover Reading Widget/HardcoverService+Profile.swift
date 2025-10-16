import Foundation
import UIKit

// MARK: - User Profile Models
struct UserProfile: Codable {
    let id: Int
    let username: String
    let bio: String?
    let image: ProfileImage?
    let flair: String?
    
    var flairs: [String]? {
        // Split flair string into array (e.g., "Supporter, Librarian" -> ["Supporter", "Librarian"])
        guard let flair = flair, !flair.isEmpty else { return nil }
        return flair.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, username, bio, image, flair
    }
}

struct ProfileImage: Codable {
    let url: String?
}

// MARK: - Profile GraphQL Responses
struct GraphQLProfileResponse: Codable {
    let data: ProfileData?
    let errors: [GraphQLProfileError]?
}

struct ProfileData: Codable {
    let me: [UserProfile]?
}

struct GraphQLProfileError: Codable {
    let message: String
}

extension HardcoverService {
    /// Fetch the current user's profile including bio and avatar
    static func fetchUserProfile() async -> UserProfile? {
        return await fetchUserProfile(username: nil)
    }
    
    /// Fetch any user's profile by username
    static func fetchUserProfile(username: String?) async -> UserProfile? {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key available")
            return nil
        }
        
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            print("❌ Invalid API URL")
            return nil
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        // GraphQL query to fetch user profile with bio and image
        let query: String
        if let username = username {
            query = """
            {
              users(where: {username: {_eq: "\(username)"}}, limit: 1) {
                id
                username
                bio
                flair
                image {
                  url
                }
              }
            }
            """
        } else {
            query = """
            {
              me {
                id
                username
                bio
                flair
                image {
                  url
                }
              }
            }
            """
        }
        
        let body: [String: Any] = ["query": query]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            print("❌ Failed to serialize request body")
            return nil
        }
        
        req.httpBody = httpBody
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Profile API response status: \(httpResponse.statusCode)")
            }
            
            // Debug: print raw response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 Profile API response: \(jsonString)")
            }
            
            let decoder = JSONDecoder()
            
            if username != nil {
                // For other users, parse from users array
                let result = try decoder.decode(GraphQLUsersProfileResponse.self, from: data)
                
                if let errors = result.errors, !errors.isEmpty {
                    print("❌ GraphQL errors: \(errors.map { $0.message }.joined(separator: ", "))")
                    return nil
                }
                
                if let profile = result.data?.users?.first {
                    print("✅ Fetched profile for @\(profile.username)")
                    return profile
                } else {
                    print("⚠️ No profile data in response")
                    return nil
                }
            } else {
                // For current user, parse from me array
                let result = try decoder.decode(GraphQLProfileResponse.self, from: data)
                
                if let errors = result.errors, !errors.isEmpty {
                    print("❌ GraphQL errors: \(errors.map { $0.message }.joined(separator: ", "))")
                    return nil
                }
                
                if let profile = result.data?.me?.first {
                    print("✅ Fetched profile for @\(profile.username)")
                    return profile
                } else {
                    print("⚠️ No profile data in response")
                    return nil
                }
            }
            
        } catch {
            print("❌ Failed to fetch user profile: \(error)")
            return nil
        }
    }
}

// MARK: - Additional response model for users query
struct GraphQLUsersProfileResponse: Codable {
    let data: UsersProfileData?
    let errors: [GraphQLProfileError]?
}

struct UsersProfileData: Codable {
    let users: [UserProfile]?
}
