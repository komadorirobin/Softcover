import SwiftUI

enum UserBookFilter: String, CaseIterable {
    case wantToRead = "Want to Read"
    case currentlyReading = "Currently Reading"
    case finished = "Finished"
}

struct UserBooksView: View {
    let username: String
    
    @State private var selectedFilter: UserBookFilter = .wantToRead
    @State private var wantToReadBooks: [BookProgress] = []
    @State private var currentlyReadingBooks: [BookProgress] = []
    @State private var finishedBooks: [FinishedBookEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Segmented Control
            Picker("Filter", selection: $selectedFilter) {
                ForEach(UserBookFilter.allCases, id: \.self) { filter in
                    Text(LocalizedStringKey(filter.rawValue))
                        .tag(filter)
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
                        Text("Loading books...", comment: "Loading books message")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Failed to load books", comment: "Error loading books")
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                } else {
                    switch selectedFilter {
                    case .wantToRead:
                        if wantToReadBooks.isEmpty {
                            emptyStateView(
                                icon: "book",
                                title: "No books in Want to Read",
                                message: "@\(username) hasn't added any books to Want to Read yet"
                            )
                        } else {
                            booksList(books: wantToReadBooks)
                        }
                    case .currentlyReading:
                        if currentlyReadingBooks.isEmpty {
                            emptyStateView(
                                icon: "book.fill",
                                title: "Not reading anything",
                                message: "@\(username) isn't currently reading any books"
                            )
                        } else {
                            booksList(books: currentlyReadingBooks)
                        }
                    case .finished:
                        if finishedBooks.isEmpty {
                            emptyStateView(
                                icon: "checkmark.circle",
                                title: "No finished books",
                                message: "@\(username) hasn't finished any books yet"
                            )
                        } else {
                            finishedBooksList()
                        }
                    }
                }
            }
        }
        .navigationTitle("@\(username)'s Books")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBooks()
        }
        .refreshable {
            await loadBooks()
        }
    }
    
    private func booksList(books: [BookProgress]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(books) { book in
                    NavigationLink {
                        BookDetailView(book: book, showFinishAction: false, allowStandaloneReviewButton: false, isOwnBook: false)
                    } label: {
                        HStack(spacing: 12) {
                            // Book Cover
                            if let imageUrl = book.coverImageUrl, let url = URL(string: imageUrl) {
                                AsyncCachedImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 60, height: 90)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 90)
                                            .cornerRadius(8)
                                    case .failure:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 60, height: 90)
                                            .cornerRadius(8)
                                            .overlay(
                                                Image(systemName: "book")
                                                    .foregroundColor(.gray)
                                            )
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 90)
                                    .cornerRadius(8)
                                    .overlay(
                                        Image(systemName: "book")
                                            .foregroundColor(.gray)
                                    )
                            }
                            
                            // Book Info
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                
                                Text(book.author)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                // Show progress for currently reading
                                if selectedFilter == .currentlyReading,
                                   book.currentPage > 0,
                                   book.totalPages > 0 {
                                    HStack(spacing: 4) {
                                        Text("\(book.currentPage) / \(book.totalPages) pages", comment: "Reading progress")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text("\(Int((Double(book.currentPage) / Double(book.totalPages)) * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.blue)
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
                    }
                }
            }
            .padding()
        }
    }
    
    private func finishedBooksList() -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(finishedBooks) { finished in
                    let book = BookProgress(
                        id: "\(finished.bookId)",
                        title: finished.title,
                        author: finished.author,
                        coverImageData: finished.coverImageData,
                        coverImageUrl: finished.coverImageUrl,
                        progress: 1.0,
                        totalPages: 0,
                        currentPage: 0,
                        bookId: finished.bookId,
                        userBookId: finished.userBookId,
                        editionId: nil,
                        originalTitle: finished.title,
                        editionAverageRating: nil,
                        userRating: finished.rating
                    )
                    
                    NavigationLink {
                        BookDetailView(book: book, showFinishAction: false, allowStandaloneReviewButton: false, isOwnBook: false)
                    } label: {
                        HStack(spacing: 12) {
                            // Book Cover
                            if let coverUrl = finished.coverImageUrl, let url = URL(string: coverUrl) {
                                AsyncCachedImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 60, height: 90)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 90)
                                            .cornerRadius(8)
                                    case .failure:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 60, height: 90)
                                            .cornerRadius(8)
                                            .overlay(
                                                Image(systemName: "book")
                                                    .foregroundColor(.gray)
                                            )
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 90)
                                    .cornerRadius(8)
                                    .overlay(
                                        Image(systemName: "book")
                                            .foregroundColor(.gray)
                                    )
                            }
                            
                            // Book Info
                            VStack(alignment: .leading, spacing: 4) {
                                Text(finished.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                
                                Text(finished.author)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                // Show finished date if available
                                Text("Finished \(finished.finishedAt, style: .date)", comment: "Finished date")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
    }
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text(LocalizedStringKey(title), comment: "Empty state title")
                .font(.headline)
            Text(LocalizedStringKey(message), comment: "Empty state message")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
    }
    
    private func loadBooks() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let wantToRead = HardcoverService.fetchUserWantToRead(username: username)
            async let currentlyReading = HardcoverService.fetchUserCurrentlyReading(username: username)
            async let finished = HardcoverService.fetchUserFinished(username: username)
            
            let (wtr, cr, fin) = try await (wantToRead, currentlyReading, finished)
            
            await MainActor.run {
                self.wantToReadBooks = wtr
                self.currentlyReadingBooks = cr
                self.finishedBooks = fin
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

#Preview {
    NavigationView {
        UserBooksView(username: "example")
    }
}
