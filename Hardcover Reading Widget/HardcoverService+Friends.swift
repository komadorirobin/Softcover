import Foundation
import UIKit

// MARK: - Friends Models
struct FriendUser: Identifiable, Codable {
    let id: Int
    let username: String
    let image: ProfileImage?
    let bio: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, image, bio
    }
}

// MARK: - Friends GraphQL Responses
struct GraphQLFollowingResponse: Codable {
    let data: FollowingData?
    let errors: [GraphQLFriendsError]?
}

struct FollowingData: Codable {
    let users: [FriendUser]?
}

struct UserFollowingEntry: Codable {
    let following_user: FriendUser?
}

struct GraphQLFollowersResponse: Codable {
    let data: FollowersData?
    let errors: [GraphQLFriendsError]?
}

struct FollowersData: Codable {
    let users: [FriendUser]?
}

struct GraphQLFriendsError: Codable {
    let message: String
}

// Simple response for fetching just the user ID
struct GraphQLUserIdResponse: Codable {
    let data: UserIdData?
    let errors: [GraphQLFriendsError]?
}

struct UserIdData: Codable {
    let me: [UserIdEntry]?
}

struct UserIdEntry: Codable {
    let id: Int
}

extension HardcoverService {
    /// Fetch the list of users the current user is following
    static func fetchFollowing() async -> [FriendUser] {
        do {
            let identity = try await LibraryAPI.identity()
            return await fetchFollowing(for: identity.username)
        } catch {
            HardcoverReadScope.failure?.record(error)
            return []
        }
    }
    
    /// Fetch the list of users a specific user is following
    static func fetchFollowing(for username: String) async -> [FriendUser] {
        do {
            guard !HardcoverConfig.apiKey.isEmpty else { throw HardcoverNetworkError.signIn }
            guard let url = URL(string: "https://hardcover.app/@\(username)/network/following") else { throw HardcoverNetworkError.invalidResponse }
            var request = URLRequest(url: url)
            request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
            try Task.checkCancellation()
            guard let html = String(data: data, encoding: .utf8),
                  let users = extractUsersFromHTML(html) else { throw HardcoverNetworkError.invalidResponse }
            return users
        } catch {
            HardcoverReadScope.failure?.record(error)
            return []
        }
    }
    
    /// Fetch the list of users following the current user
    static func fetchFollowers() async -> [FriendUser] {
        do {
            let identity = try await LibraryAPI.identity()
            return await fetchFollowers(for: identity.username)
        } catch {
            HardcoverReadScope.failure?.record(error)
            return []
        }
    }
    
    /// Fetch the list of users following a specific user
    static func fetchFollowers(for username: String) async -> [FriendUser] {
        do {
            guard !HardcoverConfig.apiKey.isEmpty else { throw HardcoverNetworkError.signIn }
            guard let url = URL(string: "https://hardcover.app/@\(username)/network/followers") else { throw HardcoverNetworkError.invalidResponse }
            var request = URLRequest(url: url)
            request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            let (data, _) = try await HardcoverHTTP.shared.data(for: request)
            try Task.checkCancellation()
            guard let html = String(data: data, encoding: .utf8),
                  let users = extractUsersFromHTML(html) else { throw HardcoverNetworkError.invalidResponse }
            return users
        } catch {
            HardcoverReadScope.failure?.record(error)
            return []
        }
    }
    
    /// Extract users array from HTML data-page attribute
    private static func extractUsersFromHTML(_ html: String) -> [FriendUser]? {
        // Find data-page attribute
        guard let dataPageRange = html.range(of: "data-page=\"") else {
            print("❌ Could not find data-page attribute")
            return nil
        }
        
        let startIndex = dataPageRange.upperBound
        guard let endIndex = html[startIndex...].range(of: "\">")?.lowerBound else {
            print("❌ Could not find end of data-page attribute")
            return nil
        }
        
        let jsonString = String(html[startIndex..<endIndex])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Could not convert JSON string to data")
            return nil
        }
        
        do {
            let pageData = try JSONDecoder().decode(InertiaPageData.self, from: jsonData)
            return pageData.props.users
        } catch {
            print("❌ Failed to decode page data: \(error)")
            return nil
        }
    }
}

// MARK: - Inertia Page Data Models
struct InertiaPageData: Codable {
    let props: InertiaProps
}

struct InertiaProps: Codable {
    let users: [FriendUser]
}
