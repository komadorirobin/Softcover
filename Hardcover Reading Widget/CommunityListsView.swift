import SwiftUI

struct CommunityListsView: View {
    @State private var lists: [CommunityList] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: ListFilter = .featured
    @State private var selectedList: CommunityList?
    
    enum ListFilter: String, CaseIterable {
        case featured = "Featured"
        case popular = "Popular"
        
        var displayName: LocalizedStringKey {
            LocalizedStringKey(self.rawValue)
        }
        
        var path: String {
            switch self {
            case .featured: return "featured"
            case .popular: return "popular"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(ListFilter.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedFilter) { _ in
                    Task { await loadLists() }
                }
                
                if isLoading {
                    ProgressView("Loading lists...")
                        .padding()
                    Spacer()
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
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(lists) { list in
                                CommunityListCard(list: list)
                                    .onTapGesture {
                                        selectedList = list
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Community Lists")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await loadLists()
        }
        .sheet(item: $selectedList) { list in
            NavigationView {
                CommunityListDetailView(list: list)
            }
        }
    }
    
    private func loadLists() async {
        isLoading = true
        errorMessage = nil
        
        let fetchedLists = await HardcoverService.fetchCommunityLists(filter: selectedFilter.path)
        
        await MainActor.run {
            if fetchedLists.isEmpty {
                errorMessage = "No lists found"
            } else {
                lists = fetchedLists
            }
            isLoading = false
        }
    }
}

struct CommunityList: Identifiable {
    let id: Int
    let name: String
    let description: String?
    let creatorUsername: String
    let creatorImage: String?
    let bookCount: Int
    let bookCovers: [String] // Up to 3 cover URLs
    let books: [ListBook] // All books in the list
}

struct CommunityListCard: View {
    let list: CommunityList
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // List header with creator info
            HStack(spacing: 8) {
                // Creator image
                if let imageUrl = list.creatorImage, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 30, height: 30)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        case .failure:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text("@\(list.creatorUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // List description
            if let description = list.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Book covers preview
            if !list.bookCovers.isEmpty {
                ZStack {
                    // Bok 2 (högra)
                    if list.bookCovers.count > 2, let url = URL(string: list.bookCovers[2]) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 55, height: 82)
                                    .cornerRadius(5)
                                    .rotationEffect(.degrees(12))
                                    .opacity(0.9)
                            }
                        }
                        .offset(x: 15, y: 18)
                        .zIndex(5)
                    }
                    
                    // Bok 1 (vänstra)
                    if list.bookCovers.count > 1, let url = URL(string: list.bookCovers[1]) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 55, height: 82)
                                    .cornerRadius(5)
                                    .rotationEffect(.degrees(-12))
                                    .opacity(0.9)
                            }
                        }
                        .offset(x: -15, y: 18)
                        .zIndex(5)
                    }
                    
                    // Bok 0 (främre)
                    if let url = URL(string: list.bookCovers[0]) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 90)
                                    .cornerRadius(6)
                                    .shadow(radius: 3)
                            }
                        }
                        .offset(x: 0, y: 10)
                        .zIndex(10)
                    }
                }
                .frame(height: 110)
                .frame(maxWidth: .infinity)
            }
            
            // Book count
            HStack(spacing: 4) {
                Image(systemName: "books.vertical.fill")
                    .font(.caption)
                Text("\(list.bookCount) books")
                    .font(.caption)
            }
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct CommunityListDetailView: View {
    let list: CommunityList
    @State private var selectedBook: BookProgress?
    @State private var showUserProfile = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Creator info header
            HStack(spacing: 12) {
                // Creator image
                if let imageUrl = list.creatorImage, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 40, height: 40)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        case .failure:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created by")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("@\(list.creatorUsername)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                showUserProfile = true
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // List title and description
                    VStack(alignment: .leading, spacing: 8) {
                        Text(list.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if let description = list.description, !description.isEmpty {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Text("\(list.bookCount) books")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                    
                    // Books section
                    if list.books.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text("No books found in this list")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(list.books) { book in
                                CommunityListBookRow(book: book)
                                    .onTapGesture {
                                        selectedBook = book.toBookProgress()
                                    }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(item: $selectedBook) { book in
            SearchResultDetailSheet(
                book: book,
                onAddComplete: { success in
                    if success {
                        // Book added successfully
                    }
                }
            )
        }
        .sheet(isPresented: $showUserProfile) {
            NavigationView {
                UserProfileView(username: list.creatorUsername)
            }
        }
    }
}

struct CommunityListBookRow: View {
    let book: ListBook
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Book cover
            if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 50, height: 75)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 75)
                            .cornerRadius(6)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 75)
                            .cornerRadius(6)
                            .overlay(
                                Image(systemName: "book.fill")
                                    .foregroundColor(.gray)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 75)
                    .cornerRadius(6)
                    .overlay(
                        Image(systemName: "book.fill")
                            .foregroundColor(.gray)
                    )
            }
            
            // Book info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(book.author ?? "Unknown Author")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

#Preview {
    CommunityListsView()
}
