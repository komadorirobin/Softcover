import SwiftUI

struct UserListsView: View {
    let username: String
    @State private var lists: [UserList] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading lists...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Failed to load lists")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await loadLists() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else if lists.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No lists yet")
                            .font(.headline)
                        Text("@\(username) hasn't created any lists yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(lists) { list in
                            NavigationLink {
                                ListDetailView(list: list, username: username)
                            } label: {
                                ListCard(list: list, username: username)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("@\(username)'s Lists")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadLists()
        }
    }
    
    private func loadLists() async {
        isLoading = true
        errorMessage = nil
        
        let fetchedLists = await HardcoverService.fetchUserLists(username: username)
        
        await MainActor.run {
            self.lists = fetchedLists
            self.isLoading = false
            
            if fetchedLists.isEmpty {
                self.errorMessage = nil // Not an error, just empty
            }
        }
    }
}

struct ListCard: View {
    let list: UserList
    let username: String
    @State private var bookCovers: [String] = []
    @State private var isLoadingCovers = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover Stack
            ZStack {
                if !bookCovers.isEmpty {
                    // Show up to 3 covers in a stack with the first one in front center
                    ForEach(Array(bookCovers.prefix(3).enumerated().reversed()), id: \.offset) { index, coverUrl in
                        if let url = URL(string: coverUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 70)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .shadow(
                                            color: .black.opacity(index == 0 ? 0.4 : 0.2),
                                            radius: index == 0 ? 6 : 3,
                                            x: 0,
                                            y: index == 0 ? 3 : 1
                                        )
                                case .empty, .failure, _:
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 50, height: 70)
                                }
                            }
                            .rotationEffect(
                                .degrees(index == 0 ? 0 : (index == 1 ? -15 : 15))
                            )
                            .offset(
                                x: index == 0 ? 0 : (index == 1 ? -12 : 12),
                                y: index == 0 ? 12 : -6
                            )
                            .scaleEffect(index == 0 ? 1.0 : 0.85)
                            .opacity(index == 0 ? 1.0 : 0.95)
                            .zIndex(Double(index == 0 ? 10 : (3 - index)))
                        }
                    }
                } else if let coverUrl = list.coverImage?.url, let url = URL(string: coverUrl) {
                    // Fallback to list cover if available
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 80)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        case .failure:
                            placeholderView
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    placeholderView
                }
            }
            .frame(width: 74, height: 84) // Space for the stacked covers
            
            // List Info
            VStack(alignment: .leading, spacing: 6) {
                Text(list.name)
                    .font(.headline)
                    .lineLimit(2)
                
                if let description = list.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 12) {
                    if let booksCount = list.booksCount {
                        Label("\(booksCount)", systemImage: "book.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let likesCount = list.likesCount {
                        Label("\(likesCount)", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .task {
            // Load book covers for the list
            guard bookCovers.isEmpty, !isLoadingCovers else { return }
            isLoadingCovers = true
            
            if let slug = list.slug {
                let books = await HardcoverService.fetchListBooks(username: username, listSlug: slug)
                let covers = books.prefix(3).compactMap { $0.coverUrl }
                await MainActor.run {
                    bookCovers = covers
                }
            }
            
            isLoadingCovers = false
        }
    }
    
    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 60, height: 80)
            .overlay(
                Image(systemName: "list.bullet")
                    .foregroundColor(.gray)
            )
    }
}

#Preview {
    NavigationStack {
        UserListsView(username: "example")
    }
}
