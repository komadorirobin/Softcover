import SwiftUI
import Foundation

struct UserSearchResult: Identifiable {
    let id: Int
    let username: String
    let name: String?
    let image: String?
    let bio: String?
}

struct UserSearchResultsView: View {
    let users: [UserSearchResult]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(users) { user in
                    NavigationLink {
                        UserProfileView(username: user.username)
                    } label: {
                        HStack(spacing: 12) {
                            // User image
                            if let imageUrl = user.image, let url = URL(string: imageUrl) {
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
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = user.name, !name.isEmpty {
                                    Text(name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                Text("@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                if let bio = user.bio, !bio.isEmpty {
                                    Text(bio)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
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
}

struct SearchBooksView: View {
    @State private var query: String = ""
    @State private var isSearching = false
    @State private var results: [HydratedBook] = []
    @State private var errorMessage: String?
    @State private var searchType: SearchType = .books
    
    enum SearchType: String, CaseIterable {
        case books = "Books"
        case users = "Users"
    }
    
    // User search results
    @State private var userResults: [UserSearchResult] = []
    
    // Read flags for search results
    @State private var finishedBookIds: Set<Int> = []
    @State private var readDates: [Int: Date] = [:]
    
    // Search detail state
    @State private var selectedSearchDetail: BookProgress?
    
    // Search history
    @State private var searchHistory: [String] = []
    private let maxHistoryItems = 10
    
    // Quick-add state
    @State private var rowAddInProgress: Int?
    @State private var quickAddPendingBook: HydratedBook?
    @State private var quickAddEditions: [Edition] = []
    @State private var quickAddSelectedEditionId: Int?
    @State private var showingQuickAddEditionSheet = false
    @State private var isLoadingQuickAddEditions = false
    @State private var showingApiSettings = false

    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false

    // Services
    private let metadataService = BookMetadataService()
    private let tagExtractor = BookTagExtractor()

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Search type picker
                Picker("Search Type", selection: $searchType) {
                    ForEach(SearchType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)
                .onChange(of: searchType) { oldValue, newValue in
                    // Clear results when switching search type
                    results = []
                    userResults = []
                    // DON'T clear query - keep it and search with new type
                    if !query.isEmpty {
                        Task { await runSearch() }
                    }
                }

                if searchType == .books && !results.isEmpty {
                    SearchResultsListView(
                        results: results,
                        finishedBookIds: finishedBookIds,
                        readDates: readDates,
                        rowAddInProgress: rowAddInProgress,
                        isLoadingQuickAddEditions: isLoadingQuickAddEditions,
                        onQuickAdd: { book in Task { await quickAddWantToReadFlow(book) } },
                        onTapResult: { book in Task { await openDetails(for: book) } }
                    )
                } else if searchType == .users && !userResults.isEmpty {
                    UserSearchResultsView(users: userResults)
                } else if query.isEmpty {
                    // Empty state - prompt to search with history
                    ScrollView {
                        VStack(spacing: 24) {
                            Spacer(minLength: 40)
                            
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(searchType == .books ? "Search for books" : "Search for users")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Text(searchType == .books ? "Try searching by title or author" : "Find readers on Hardcover")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            // Search history section
                            if !searchHistory.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Recent Searches")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Button("Clear") {
                                            clearSearchHistory()
                                        }
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                    }
                                    .padding(.horizontal)
                                    
                                    ForEach(searchHistory, id: \.self) { term in
                                        Button {
                                            query = term
                                            Task { await runSearch() }
                                        } label: {
                                            HStack {
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .foregroundColor(.secondary)
                                                Text(term)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                Image(systemName: "arrow.up.left")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal)
                                            .background(Color(UIColor.secondarySystemBackground))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.top, 20)
                            }
                            
                            Spacer()
                        }
                    }
                } else if !query.isEmpty && (results.isEmpty && userResults.isEmpty) {
                    VStack(spacing: 10) {
                        Image(systemName: searchType == .books ? "book" : "person")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No \(searchType.rawValue.lowercased()) found")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    Spacer()
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { 
                        showingApiSettings = true 
                    } label: { 
                        Image(systemName: "gearshape") 
                    }
                }
                
                if !query.isEmpty || !results.isEmpty || !userResults.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            // Clear search and results
                            query = ""
                            results = []
                            userResults = []
                            errorMessage = nil
                        } label: {
                            Text("Clear")
                                .font(.body)
                        }
                    }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(searchType == .books ? "Title, author, or ISBN" : "Username or name")
            )
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .onChange(of: query) { oldValue, newValue in
                if !newValue.isEmpty && newValue != oldValue {
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                        if query == newValue {
                            await runSearch()
                        }
                    }
                }
            }
        }
        .task {
            loadSearchHistory()
        }
        .sheet(item: $selectedSearchDetail) { book in
            SearchResultDetailSheet(
                book: book,
                onAddComplete: { success in
                    if success {
                        onDone(true)
                    }
                }
            )
        }
        .sheet(isPresented: $showingQuickAddEditionSheet) {
            if let pending = quickAddPendingBook {
                EditionSelectionSheet(
                    bookTitle: pending.title,
                    currentEditionId: quickAddSelectedEditionId,
                    editions: quickAddEditions,
                    onCancel: {
                        quickAddPendingBook = nil
                        quickAddEditions = []
                        quickAddSelectedEditionId = nil
                    },
                    onSave: { chosenId in
                        Task {
                            await addSearchResultToWantToRead(pending, editionId: chosenId)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingApiSettings) {
            ApiKeySettingsView { _ in
                // No specific action needed
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSearchHistory() {
        if let saved = AppGroup.defaults.stringArray(forKey: "SearchHistory") {
            searchHistory = saved
        }
    }
    
    private func saveToSearchHistory(_ searchTerm: String) {
        let trimmed = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Remove if already exists
        searchHistory.removeAll { $0 == trimmed }
        // Add to beginning
        searchHistory.insert(trimmed, at: 0)
        // Keep only max items
        if searchHistory.count > maxHistoryItems {
            searchHistory = Array(searchHistory.prefix(maxHistoryItems))
        }
        
        AppGroup.defaults.set(searchHistory, forKey: "SearchHistory")
    }
    
    private func clearSearchHistory() {
        searchHistory = []
        AppGroup.defaults.removeObject(forKey: "SearchHistory")
    }
    
    private func runSearch() async {
        errorMessage = nil
        let raw = query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        
        // Save to search history
        await MainActor.run {
            saveToSearchHistory(raw)
        }
        
        isSearching = true
        
        if searchType == .books {
            let (titlePart, authorPart) = parseQuery(raw)
            let list = await HardcoverService.searchBooks(
                title: titlePart,
                author: authorPart?.isEmpty == false ? authorPart : nil
            )
            await MainActor.run {
                self.results = list
                self.userResults = []
                self.isSearching = false
                if list.isEmpty {
                    self.errorMessage = "No results. Try another search."
                }
            }
            await refreshFinishedFlags()
        } else {
            // Search for users
            let users = await HardcoverService.searchUsers(query: raw)
            await MainActor.run {
                self.userResults = users
                self.results = []
                self.isSearching = false
                if users.isEmpty {
                    self.errorMessage = "No users found. Try another search."
                }
            }
        }
    }
    
    private func refreshFinishedFlags() async {
        let ids = results.map { $0.id }
        guard !ids.isEmpty else {
            await MainActor.run { 
                finishedBookIds = []
                readDates = [:]
            }
            return
        }
        let finishedBooksWithDates = await metadataService.fetchFinishedBooksWithDates(for: ids)
        await MainActor.run { 
            finishedBookIds = Set(finishedBooksWithDates.keys)
            readDates = finishedBooksWithDates
        }
    }
    
    private func parseQuery(_ q: String) -> (title: String, author: String?) {
        let lower = q.lowercased()
        guard let range = lower.range(of: "author:") else {
            return (q, nil)
        }
        let authorStartIndex = range.upperBound
        let titlePart = q[..<range.lowerBound].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let authorRaw = q[authorStartIndex...].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        if authorRaw.hasPrefix("\"") {
            if let endQuote = authorRaw.dropFirst().firstIndex(of: "\"") {
                let name = authorRaw[authorRaw.index(after: authorRaw.startIndex)..<endQuote]
                return (titlePart, String(name).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            } else {
                return (titlePart, String(authorRaw.dropFirst()).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            }
        } else {
            return (titlePart, authorRaw)
        }
    }
    
    private func openDetails(for book: HydratedBook) async {
        let detail = await HardcoverService.fetchBookDetailsById(bookId: book.id, userBookId: nil, imageMaxPixel: 360, compression: 0.8)
        await MainActor.run {
            if let detail {
                selectedSearchDetail = detail
            } else {
                let author = book.contributions?.first?.author?.name ?? "Unknown Author"
                let minimal = BookProgress(
                    id: "search-\(book.id)",
                    title: book.title,
                    author: author,
                    coverImageData: nil,
                    progress: 0.0,
                    totalPages: 0,
                    currentPage: 0,
                    bookId: book.id,
                    userBookId: nil,
                    editionId: nil,
                    originalTitle: book.title,
                    editionAverageRating: nil,
                    userRating: nil,
                    bookDescription: nil
                )
                selectedSearchDetail = minimal
            }
        }
    }
    
    private func quickAddWantToReadFlow(_ book: HydratedBook) async {
        if skipEditionPickerOnAdd {
            await MainActor.run { rowAddInProgress = book.id }
            await addSearchResultToWantToRead(book, editionId: nil)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                rowAddInProgress = nil
            }
            return
        }
        
        await MainActor.run {
            rowAddInProgress = book.id
            isLoadingQuickAddEditions = true
            quickAddPendingBook = nil
            quickAddEditions = []
            quickAddSelectedEditionId = nil
        }
        
        let editions = await HardcoverService.fetchEditions(for: book.id)
        if editions.count <= 1 {
            let eid = editions.first?.id
            await addSearchResultToWantToRead(book, editionId: eid)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                rowAddInProgress = nil
            }
            return
        }
        
        await MainActor.run {
            isLoadingQuickAddEditions = false
            rowAddInProgress = nil
            quickAddPendingBook = book
            quickAddEditions = editions
            quickAddSelectedEditionId = nil
            showingQuickAddEditionSheet = true
        }
    }
    
    private func addSearchResultToWantToRead(_ book: HydratedBook, editionId: Int?) async {
        await MainActor.run { rowAddInProgress = book.id }
        let ok = await HardcoverService.addBookToWantToRead(bookId: book.id, editionId: editionId)
        await MainActor.run {
            rowAddInProgress = nil
            if ok {
                onDone(true)
            }
            showingQuickAddEditionSheet = false
            quickAddPendingBook = nil
            quickAddEditions = []
            quickAddSelectedEditionId = nil
        }
    }
}

#Preview { SearchBooksView { _ in } }
