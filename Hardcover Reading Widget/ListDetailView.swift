import SwiftUI

struct ListDetailView: View {
    let list: UserList
    let username: String
    @State private var books: [ListBook] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading list...")
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
                        Text("Failed to load list")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await loadBooks() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    // List Header
                    VStack(alignment: .leading, spacing: 12) {
                        if let description = list.description, !description.isEmpty {
                            Text(description.decodedHTMLEntities)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                        
                        HStack(spacing: 16) {
                            if let booksCount = list.booksCount {
                                Label("\(booksCount) books", systemImage: "book.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let likesCount = list.likesCount {
                                Label("\(likesCount) likes", systemImage: "heart.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Books in the list
                    if books.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No books in this list")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                                if let bookId = book.bookId {
                                    NavigationLink(destination: BookDetailView(
                                        book: BookProgress(
                                            id: "\(bookId)",
                                            title: book.title,
                                            author: book.author ?? "Unknown Author",
                                            coverImageData: nil,
                                            coverImageUrl: book.coverUrl,
                                            progress: 0.0,
                                            totalPages: 0,
                                            currentPage: 0,
                                            bookId: bookId,
                                            userBookId: nil,
                                            editionId: nil,
                                            originalTitle: book.title,
                                            editionAverageRating: nil,
                                            userRating: nil,
                                            bookDescription: nil
                                        ),
                                        showFinishAction: false,
                                        allowStandaloneReviewButton: true
                                    )) {
                                        ListBookRow(book: book)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    ListBookRow(book: book)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadBooks()
        }
    }
    
    private func loadBooks() async {
        isLoading = true
        errorMessage = nil
        
        // Fetch books from the list
        guard let slug = list.slug else {
            await MainActor.run {
                self.books = []
                self.isLoading = false
                self.errorMessage = "List slug not available"
            }
            return
        }
        
        let fetchedBooks = await HardcoverService.fetchListBooks(username: username, listSlug: slug)
        
        await MainActor.run {
            self.books = fetchedBooks
            self.isLoading = false
        }
    }
}

struct ListBookRow: View {
    let book: ListBook
    
    var body: some View {
        HStack(spacing: 12) {
            // Book Cover
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
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    case .failure:
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 75)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 75)
            }
            
            // Book Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        ListDetailView(
            list: UserList(
                id: 1,
                name: "Example List",
                description: "A sample list",
                booksCount: 10,
                likesCount: 5,
                slug: "example",
                user: nil,
                coverImage: nil
            ),
            username: "example"
        )
    }
}
