import SwiftUI

struct CommunityUpcomingView: View {
    @State private var upcomingBooks: [CommunityUpcomingBook] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: TimeFilter = .oneMonth
    @State private var selectedBook: BookProgress?
    
    enum TimeFilter: String, CaseIterable {
        case recent = "Recent"
        case oneMonth = "1 Month"
        case threeMonths = "3 Months"
        case oneYear = "1 Year"
        
        var displayName: LocalizedStringKey {
            LocalizedStringKey(self.rawValue)
        }
        
        var path: String {
            switch self {
            case .recent: return "recent"
            case .oneMonth: return "month"
            case .threeMonths: return "quarter"
            case .oneYear: return "year"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter picker
            Picker("Time Range", selection: $selectedFilter) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedFilter) { _ in
                Task { await loadUpcomingBooks() }
            }
            
            if isLoading {
                ProgressView("Loading upcoming releases...")
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
                        ForEach(upcomingBooks) { book in
                            CommunityUpcomingBookCard(book: book)
                                .onTapGesture {
                                    selectedBook = book.toBookProgress()
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadUpcomingBooks()
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
    }
    
    private func loadUpcomingBooks() async {
        isLoading = true
        errorMessage = nil
        
        let books = await HardcoverService.fetchCommunityUpcomingReleases(filter: selectedFilter.path)
        
        await MainActor.run {
            if books.isEmpty {
                errorMessage = "No upcoming releases found"
            } else {
                upcomingBooks = books
            }
            isLoading = false
        }
    }
}

struct CommunityUpcomingBook: Identifiable {
    let id: Int
    let title: String
    let author: String
    let coverUrl: String?
    let releaseDate: String?
    let contributionsCount: Int
    
    func toBookProgress() -> BookProgress {
        return BookProgress(
            id: "\(id)",
            title: title,
            author: author,
            coverImageData: nil,
            coverImageUrl: coverUrl,
            progress: 0.0,
            totalPages: 0,
            currentPage: 0,
            bookId: id,
            userBookId: nil,
            editionId: nil,
            originalTitle: title,
            editionAverageRating: nil,
            userRating: nil,
            bookDescription: nil
        )
    }
}

struct CommunityUpcomingBookCard: View {
    let book: CommunityUpcomingBook
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Book cover
            if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 60, height: 90)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 90)
                            .cornerRadius(6)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 90)
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
                    .frame(width: 60, height: 90)
                    .cornerRadius(6)
                    .overlay(
                        Image(systemName: "book.fill")
                            .foregroundColor(.gray)
                    )
            }
            
            // Book info
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let releaseDate = book.releaseDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text(releaseDate)
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
                
                if book.contributionsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                        Text("\(book.contributionsCount) reading")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
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

#Preview {
    NavigationView {
        CommunityUpcomingView()
    }
}
