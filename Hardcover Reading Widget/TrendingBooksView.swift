import SwiftUI

struct TrendingBooksView: View {
    @State private var trending: [HardcoverService.TrendingBook] = []
    @State private var trendingLoading = false
    @State private var trendingError: String?
    @State private var trendingAddInProgress: Int?
    @State private var selectedTrending: HardcoverService.TrendingBook?
    @State private var selectedFilter: TimeFilter = .lastMonth
    
    let onDone: (Bool) -> Void
    
    enum TimeFilter: String, CaseIterable {
        case lastMonth = "Last Month"
        case threeMonths = "3 Months"
        case oneYear = "1 Year"
        case allTime = "All Time"
        
        var displayName: LocalizedStringKey {
            LocalizedStringKey(self.rawValue)
        }
        
        var path: String {
            switch self {
            case .lastMonth: return "month"
            case .threeMonths: return "recent"
            case .oneYear: return "year"
            case .allTime: return "all"
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
                Task { await loadTrending(force: true) }
            }
            
            Group {
            if trendingLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading trending books...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = trendingError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Failed to load trending books")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await loadTrending(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if trending.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "flame")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No trending books found")
                        .font(.headline)
                    Button("Reload") {
                        Task { await loadTrending(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(trending) { item in
                            TrendingBookCard(
                                book: item,
                                isAddInProgress: trendingAddInProgress == item.id,
                                onTap: { selectedTrending = item },
                                onQuickAdd: { Task { await addTrendingBook(item) } }
                            )
                        }
                    }
                    .padding()
                }
            }
            }  // Group
        }  // VStack
        .task {
            await loadTrending(force: false)
        }
        .sheet(item: $selectedTrending) { item in
            TrendingBookDetailSheet(
                item: item,
                isWorking: trendingAddInProgress == item.id,
                onAddWithEdition: { chosenId in
                    Task { await addTrendingBook(item, editionId: chosenId) }
                }
            )
        }
    }  // body
    
    private func loadTrending(force: Bool) async {
        await MainActor.run { trendingLoading = true }
        
        let books = await HardcoverService.fetchTrendingBooks(timeFilter: selectedFilter.path)
        
        await MainActor.run {
            trendingLoading = false
            if books.isEmpty {
                trendingError = "No trending books available"
            } else {
                trending = books
                trendingError = nil
            }
        }
    }
    
    private func addTrendingBook(_ item: HardcoverService.TrendingBook, editionId: Int? = nil) async {
        await MainActor.run {
            trendingAddInProgress = item.id
        }
        
        let success = await HardcoverService.addBookToWantToRead(
            bookId: item.id,
            editionId: editionId
        )
        
        await MainActor.run {
            trendingAddInProgress = nil
            if success {
                onDone(true)
            }
        }
    }
}

struct TrendingBookCard: View {
    let book: HardcoverService.TrendingBook
    let isAddInProgress: Bool
    let onTap: () -> Void
    let onQuickAdd: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Book cover
                if let urlString = book.coverImageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 90)
                                .cornerRadius(6)
                        case .empty, .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 90)
                                .cornerRadius(6)
                                .overlay(
                                    Image(systemName: "book.fill")
                                        .foregroundColor(.gray)
                                )
                        @unknown default:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 90)
                                .cornerRadius(6)
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
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Trending")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                    
                    Text(book.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if book.usersCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                            Text("\(book.usersCount) reading")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                // Quick add button
                Button(action: onQuickAdd) {
                    if isAddInProgress {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .disabled(isAddInProgress)
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TrendingBooksView(onDone: { _ in })
}
