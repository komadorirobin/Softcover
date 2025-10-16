import SwiftUI

struct ProfileView: View {
    @State private var profile: UserProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingApiSettings = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading profile...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Failed to load profile")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await loadProfile() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                    .padding(.horizontal)
                } else if let profile = profile {
                    ScrollView {
                        VStack(spacing: 24) {
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
                                NavigationLink {
                                    StatsView()
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
                                
                                NavigationLink {
                                    HistoryView()
                                } label: {
                                    HStack {
                                        Image(systemName: "clock.fill")
                                            .foregroundColor(.green)
                                            .frame(width: 30)
                                        Text("Reading History")
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
                                
                                NavigationLink {
                                    FriendsView()
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
                            
                            Spacer()
                        }
                    }
                    .background(Color(UIColor.systemGroupedBackground))
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No profile data available")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { 
                        showingApiSettings = true 
                    } label: { 
                        Image(systemName: "gearshape") 
                    }
                }
            }
            .sheet(isPresented: $showingApiSettings) {
                ApiKeySettingsView { _ in
                    Task {
                        await loadProfile()
                    }
                }
            }
        }
        .task {
            await loadProfile()
        }
    }
    
    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        
        let fetchedProfile = await HardcoverService.fetchUserProfile()
        
        await MainActor.run {
            if let fetchedProfile = fetchedProfile {
                self.profile = fetchedProfile
                self.errorMessage = nil
            } else {
                self.errorMessage = "Could not load profile data"
            }
            self.isLoading = false
        }
    }
}

struct FlairBadge: View {
    let flair: String
    
    private var flairInfo: (icon: String, color: Color) {
        switch flair.lowercased() {
        case "supporter":
            return ("heart.fill", .pink)
        case "librarian":
            return ("book.fill", .blue)
        case "moderator":
            return ("shield.fill", .green)
        case "admin":
            return ("crown.fill", .orange)
        default:
            return ("star.fill", .gray)
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: flairInfo.icon)
                .font(.system(size: 10))
            Text(flair)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(flairInfo.color)
        .cornerRadius(12)
    }
}

#Preview {
    ProfileView()
}

