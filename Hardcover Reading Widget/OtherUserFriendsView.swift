import SwiftUI

struct OtherUserFriendsView: View {
    let username: String
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
                        Text(selectedFilter == .following ? "Not following anyone" : "No followers")
                            .font(.headline)
                        Text(selectedFilter == .following ? "@\(username) is not following anyone yet" : "@\(username) doesn't have any followers yet")
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
        .navigationTitle("@\(username)'s Friends")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadFriends()
        }
    }
    
    private func loadFriends() async {
        isLoading = true
        errorMessage = nil
        
        async let followingResult = HardcoverService.fetchFollowing(for: username)
        async let followersResult = HardcoverService.fetchFollowers(for: username)
        
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

#Preview {
    NavigationStack {
        OtherUserFriendsView(username: "example")
    }
}
