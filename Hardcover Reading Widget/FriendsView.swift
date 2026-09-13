import SwiftUI

enum FriendsFilter: String, CaseIterable {
    case following = "Following"
    case followers = "Followers"
}

struct FriendsView: View {
    @State private var selectedFilter = FriendsFilter.following
    @StateObject private var store = ExploreLoadState<FriendUser>()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $selectedFilter) {
                ForEach(FriendsFilter.allCases, id: \.self) { filter in
                    Text(LocalizedStringKey(filter.rawValue)).tag(filter)
                }
            }
            .pickerStyle(.segmented).padding()
            List {
                ExploreLoadFeedback(isLoading: store.isLoading, error: store.error,
                                    isEmpty: store.items.isEmpty,
                                    emptyTitle: selectedFilter == .following ? "Not following anyone yet" : "No followers yet") {
                    Task { await load(refresh: true) }
                }
                ForEach(store.items) { user in
                    NavigationLink { UserProfileView(username: user.username) } label: { FriendRow(user: user) }
                }
            }
            .listStyle(.plain)
            .refreshable { await load(refresh: true) }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedFilter) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .hardcoverAccountDidChange)) { _ in
            store.reset()
            Task { await load() }
        }
    }

    @MainActor private func load(refresh: Bool = false) async {
        let filter = selectedFilter
        await store.load(key: filter.rawValue, refresh: refresh) {
            try await HardcoverReadScope.checked {
                if filter == .following { return await HardcoverService.fetchFollowing() }
                return await HardcoverService.fetchFollowers()
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
