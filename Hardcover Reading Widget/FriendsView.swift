import SwiftUI

enum FriendsFilter: String, CaseIterable {
    case following = "Following"
    case followers = "Followers"
}

struct FriendsView: View {
    @State private var selectedFilter: FriendsFilter = .following
    @State private var following: [FriendUser] = []
    @State private var followers: [FriendUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private var displayedUsers: [FriendUser] {
        switch selectedFilter {
        case .following:
            return following
        case .followers:
            return followers
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Segmented Control
            Picker("Filter", selection: $selectedFilter) {
                ForEach(FriendsFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading friends...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Failed to load friends")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await loadFriends() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                } else if displayedUsers.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: selectedFilter == .following ? "person.2" : "person.wave.2")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text(selectedFilter == .following ? "Not following anyone yet" : "No followers yet")
                            .font(.headline)
                        Text(selectedFilter == .following ? "Start following other users to see them here" : "Other users will appear here when they follow you")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                } else {
                    List(displayedUsers) { user in
                        NavigationLink {
                            UserProfileView(username: user.username)
                        } label: {
                            FriendRow(user: user)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadFriends()
        }
    }
    
    private func loadFriends() async {
        isLoading = true
        errorMessage = nil
        
        async let followingResult = HardcoverService.fetchFollowing()
        async let followersResult = HardcoverService.fetchFollowers()
        
        let (fetchedFollowing, fetchedFollowers) = await (followingResult, followersResult)
        
        await MainActor.run {
            self.following = fetchedFollowing
            self.followers = fetchedFollowers
            self.isLoading = false
            
            if fetchedFollowing.isEmpty && fetchedFollowers.isEmpty {
                self.errorMessage = nil // Not an error, just empty
            }
        }
    }
}

struct FriendRow: View {
    let user: FriendUser
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Image
            if let imageUrl = user.image?.url, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 50, height: 50)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    case .failure:
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text("@\(user.username)")
                    .font(.headline)
                
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        FriendsView()
    }
}
