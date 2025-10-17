import SwiftUI

struct UserProfileView: View {
    let username: String
    @State private var profile: UserProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowing = false
    @State private var isCheckingFollowStatus = true
    @State private var isUpdatingFollow = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    ProgressView("Loading profile...")
                        .padding(.top, 50)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let profile = profile {
                    // Profile Header
                    VStack(spacing: 16) {
                        // Profile Image
                        if let imageUrl = profile.image?.url, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 120, height: 120)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                case .failure:
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 120))
                                        .foregroundColor(.gray)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 120))
                                .foregroundColor(.gray)
                        }
                        
                        // Username
                        Text("@\(profile.username)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        // Flairs
                        if let flairs = profile.flairs, !flairs.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(flairs, id: \.self) { flair in
                                    FlairBadge(flair: flair)
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        // Following Badge/Button
                        if !isCheckingFollowStatus {
                            if isFollowing {
                                Button {
                                    Task { await unfollowUser() }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                        Text("Following")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.green)
                                    .cornerRadius(20)
                                }
                                .disabled(isUpdatingFollow)
                                .opacity(isUpdatingFollow ? 0.6 : 1.0)
                            } else {
                                Button {
                                    Task { await followUser() }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.caption)
                                        Text("Follow")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(20)
                                }
                                .disabled(isUpdatingFollow)
                                .opacity(isUpdatingFollow ? 0.6 : 1.0)
                            }
                        }
                        
                        // Bio
                        if let bio = profile.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 20)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Navigation Links
                    VStack(spacing: 0) {
                        // Books (only for other users, not the logged-in user)
                        let loggedInUsername = AppGroup.defaults.string(forKey: "HardcoverUsername") ?? ""
                        if !loggedInUsername.isEmpty && profile.username.lowercased() != loggedInUsername.lowercased() {
                            NavigationLink {
                                UserBooksView(username: profile.username)
                            } label: {
                                HStack {
                                    Image(systemName: "books.vertical.fill")
                                        .foregroundColor(.green)
                                        .frame(width: 30)
                                    Text("Books")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                            }
                            
                            Divider()
                                .padding(.leading, 46)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                        }
                        
                        // Reading Stats
                        NavigationLink {
                            OtherUserStatsView(username: profile.username)
                        } label: {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 30)
                                Text("Reading Stats")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        }
                        
                        Divider()
                            .padding(.leading, 46)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        
                        // Lists
                        NavigationLink {
                            UserListsView(username: profile.username)
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet")
                                    .foregroundColor(.orange)
                                    .frame(width: 30)
                                Text("Lists")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        }
                        
                        Divider()
                            .padding(.leading, 46)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        
                        // Friends
                        NavigationLink {
                            OtherUserFriendsView(username: profile.username)
                        } label: {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(.purple)
                                    .frame(width: 30)
                                Text("Friends")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                        }
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
            await checkFollowStatus()
        }
    }
    
    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        
        if let fetchedProfile = await HardcoverService.fetchUserProfile(username: username) {
            profile = fetchedProfile
        } else {
            errorMessage = "Failed to load profile"
        }
        
        isLoading = false
    }
    
    private func checkFollowStatus() async {
        isCheckingFollowStatus = true
        
        // Fetch list of users we're following
        let followingUsers = await HardcoverService.fetchFollowing()
        
        await MainActor.run {
            // Check if this user is in our following list
            isFollowing = followingUsers.contains { $0.username.lowercased() == username.lowercased() }
            isCheckingFollowStatus = false
        }
    }
    
    private func followUser() async {
        guard !isUpdatingFollow, let userId = profile?.id else { return }
        
        await MainActor.run { 
            isUpdatingFollow = true
        }
        
        let success = await HardcoverService.followUserById(userId: userId)
        
        await MainActor.run {
            isUpdatingFollow = false
            if success {
                // Update UI immediately
                isFollowing = true
                print("✅ UI updated: now following \(username)")
            } else {
                print("❌ Failed to follow \(username)")
            }
        }
    }
    
    private func unfollowUser() async {
        guard !isUpdatingFollow, let userId = profile?.id else { return }
        
        await MainActor.run { 
            isUpdatingFollow = true
        }
        
        let success = await HardcoverService.unfollowUserById(userId: userId)
        
        await MainActor.run {
            isUpdatingFollow = false
            if success {
                // Update UI immediately
                isFollowing = false
                print("✅ UI updated: unfollowed \(username)")
            } else {
                print("❌ Failed to unfollow \(username)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        UserProfileView(username: "example")
    }
}
