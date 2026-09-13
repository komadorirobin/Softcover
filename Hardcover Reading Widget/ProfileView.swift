import SwiftUI

struct ProfileView: View {
    @State private var profile: UserProfile?
    @State private var goals: [ReadingGoal] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingApiSettings = false
    @State private var generation = UUID()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    InlineLoadError(message: errorMessage) { Task { await loadProfile() } }
                }
                if isLoading && profile == nil { ProgressView().frame(maxWidth: .infinity) }
                if let profile {
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            AsyncCachedImage(url: URL(string: profile.image?.url ?? "")) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
                            }
                            .frame(width: 56, height: 56).clipShape(Circle()).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("@\(profile.username)").font(.headline)
                                if let flairs = profile.flairs, !flairs.isEmpty {
                                    ViewThatFits(in: .horizontal) {
                                        HStack { ForEach(flairs, id: \.self) { FlairBadge(flair: $0) } }
                                        VStack(alignment: .leading) { ForEach(flairs, id: \.self) { FlairBadge(flair: $0) } }
                                    }
                                }
                                if let bio = profile.bio, !bio.isEmpty {
                                    Text(bio).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    if !goals.isEmpty {
                        Section("Reading Goals") {
                            ForEach(goals, id: \.id) { goal in
                                NavigationLink { StatsView() } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(goal.description ?? NSLocalizedString("Reading Goal", comment: "")).font(.subheadline)
                                        ProgressView(value: min(max(goal.percentComplete, 0), 1))
                                        Text("\(goal.progress) / \(goal.goal) \(goal.metric == "page" ? NSLocalizedString("pages", comment: "") : NSLocalizedString("books", comment: ""))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    Section("Library") {
                        NavigationLink { StatsView() } label: { Label("Reading Stats", systemImage: "chart.bar") }
                        NavigationLink { HistoryView() } label: { Label("Reading History", systemImage: "clock") }
                        NavigationLink { UserListsView(username: profile.username) } label: { Label("Lists", systemImage: "list.bullet") }
                        NavigationLink { PromptsView() } label: { Label("Answered Prompts", systemImage: "questionmark.bubble") }
                    }
                    Section("Community") {
                        NavigationLink { FriendsView() } label: { Label("Friends", systemImage: "person.2") }
                        NavigationLink { FeedView() } label: { Label("Feed", systemImage: "newspaper") }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingApiSettings = true }
                }
            }
            .sheet(isPresented: $showingApiSettings) { ApiKeySettingsView() }
            .refreshable { await loadProfile() }
            .task { if profile == nil { await loadProfile() } }
            .onReceive(NotificationCenter.default.publisher(for: .hardcoverAccountDidChange)) { _ in
                generation = UUID(); profile = nil; goals = []
                Task { await loadProfile() }
            }
        }
    }

    @MainActor private func loadProfile() async {
        let request = UUID()
        let account = HardcoverConfig.authorizationHeaderValue
        generation = request
        isLoading = true; errorMessage = nil
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await HardcoverReadScope.checked { await HardcoverService.fetchUserProfile() }
            try Task.checkCancellation()
            guard request == generation, account == HardcoverConfig.authorizationHeaderValue else { return }
            guard let result else { throw HardcoverNetworkError.invalidResponse }
            profile = result
            let loadedGoals = try await HardcoverReadScope.checked { await HardcoverService.fetchReadingGoals() }
            try Task.checkCancellation()
            guard request == generation, account == HardcoverConfig.authorizationHeaderValue else { return }
            goals = loadedGoals
        } catch {
            guard !Task.isCancelled, request == generation else { return }
            errorMessage = error.localizedDescription
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
