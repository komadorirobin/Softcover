import SwiftUI
import Foundation

// MARK: - Compatibility Functions
// These functions maintain compatibility with existing code that expects file-scoped functions

fileprivate func extractGenres(_ value: Any?) -> [String]? {
    BookTagExtractor.extractGenres(value)
}

fileprivate func extractGenres(fromCachedTags value: Any?) -> [String]? {
    BookTagExtractor.extractGenres(fromCachedTags: value)
}

fileprivate func extractMoods(_ value: Any?) -> [String]? {
    BookTagExtractor.extractMoods(value)
}

fileprivate func extractMoods(fromCachedTags value: Any?) -> [String]? {
    BookTagExtractor.extractMoods(fromCachedTags: value)
}

fileprivate func extractGenresFromTaggings(_ value: Any?) -> [String]? {
    BookTagExtractor.extractGenresFromTaggings(value)
}

fileprivate func extractMoodsFromTaggings(_ value: Any?) -> [String]? {
    BookTagExtractor.extractMoodsFromTaggings(value)
}

// MARK: - Query Helper Functions
// These delegate to BookMetadataService for cleaner code

fileprivate func queryBookCachedGenres(url: URL, bookId: Int) async -> [String]? {
    await BookMetadataService.queryBookCachedGenres(url: url, bookId: bookId)
}

fileprivate func queryUserBookCachedGenres(url: URL, userBookId: Int) async -> [String]? {
    await BookMetadataService.queryUserBookCachedGenres(url: url, userBookId: userBookId)
}

fileprivate func queryBookMoodsViaTaggings(url: URL, bookId: Int) async -> [String]? {
    await BookMetadataService.queryBookMoodsViaTaggings(url: url, bookId: bookId)
}

fileprivate func queryEditionBookMoodsViaTaggings(url: URL, editionId: Int) async -> [String]? {
    await BookMetadataService.queryEditionBookMoodsViaTaggings(url: url, editionId: editionId)
}

fileprivate func queryUserBookMoodsViaTaggings(url: URL, userBookId: Int) async -> [String]? {
    await BookMetadataService.queryUserBookMoodsViaTaggings(url: url, userBookId: userBookId)
}

fileprivate func queryBookCachedMoods(url: URL, bookId: Int) async -> [String]? {
    await BookMetadataService.queryBookCachedMoods(url: url, bookId: bookId)
}

fileprivate func queryEditionBookCachedMoods(url: URL, editionId: Int) async -> [String]? {
    await BookMetadataService.queryEditionBookCachedMoods(url: url, editionId: editionId)
}

fileprivate func queryUserBookCachedMoods(url: URL, userBookId: Int) async -> [String]? {
    await BookMetadataService.queryUserBookCachedMoods(url: url, userBookId: userBookId)
}

struct SearchBooksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var isSearching = false
    @State private var results: [HydratedBook] = []
    @State private var errorMessage: String?
    
    // Mark: Read flags for search results
    @State private var finishedBookIds: Set<Int> = []
    
    // Trending state
    @State private var trending: [HardcoverService.TrendingBook] = []
    @State private var trendingLoading = false
    @State private var trendingError: String?
    @State private var trendingAddInProgress: Int?
    // Vald trending-bok för detaljvy
    @State private var selectedTrending: HardcoverService.TrendingBook?
    
    // NYTT: vald sökträff som BookProgress för detaljark
    @State private var selectedSearchDetail: BookProgress?
    
    // NYTT: per-rad add-state för sökresultatens snabbknapp
    @State private var rowAddInProgress: Int?
    
    // NYTT: Quick-add editionsflöde för sökträffens snabbknapp
    @State private var quickAddPendingBook: HydratedBook?
    @State private var quickAddEditions: [Edition] = []
    @State private var quickAddSelectedEditionId: Int?
    @State private var showingQuickAddEditionSheet = false
    @State private var isLoadingQuickAddEditions = false

    // NEW: Preference to skip edition picker on add
    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Title or author (tip: author:Herbert)", text: $query, onCommit: { Task { await runSearch() } })
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .accessibilityLabel("Search books")
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    Button(action: { Task { await runSearch() } }) {
                        HStack {
                            if isSearching { ProgressView().scaleEffect(0.8) }
                            Text(isSearching ? "Searching…" : "Search")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSearching || query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)

                // Trending section – visa bara när det inte finns några sökresultat
                if results.isEmpty {
                    VStack(spacing: 0) { // Ingen extra vertikal spacing mellan rubriken och böckerna
                        HStack {
                            Text("Trending this month")
                                .font(.system(size: 28, weight: .bold)) // Stor rubrik
                            Spacer()
                            IfTrendingLoadingView(trendingLoading: trendingLoading) {
                                Task { await loadTrending(force: true) }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 0) // Ingen bottenmarginal under rubriken
                        
                        // Visa ev. fel endast när listan är tom (då finns inga böcker under rubriken)
                        if let tErr = trendingError, trending.isEmpty {
                            Text(tErr)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 6)
                        }
                        
                        // Böcker direkt under rubriken med top-alignment så omslagen linjerar i toppen
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) { // Viktigt: alignment: .top
                                if trendingLoading && trending.isEmpty {
                                    ForEach(0..<8, id: \.self) { _ in
                                        TrendingSkeletonCell()
                                    }
                                } else {
                                    ForEach(trending) { item in
                                        TrendingBookCell(
                                            item: item,
                                            isWorking: trendingAddInProgress == item.id,
                                            onTap: {
                                                Task { await addTrendingBook(item) }
                                            },
                                            onOpen: {
                                                selectedTrending = item
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 0)   // Ingen toppmarginal
                        .offset(y: 8)      // Dra upp innehållet lite för att minska upplevt mellanrum
                    }
                    .padding(.top, 24) // Större avstånd från sökfältet ovanför
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                if results.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("Search Hardcover for books")
                            .foregroundColor(.secondary)
                            .font(.headline)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach($results, id: \.id) { book in
                            HStack(spacing: 12) {
                                cover(for: book)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.wrappedValue.title).font(.subheadline).lineLimit(2)
                                    let author = book.wrappedValue.contributions?.first?.author?.name ?? "Unknown Author"
                                    Text(author).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    
                                    if finishedBookIds.contains(book.wrappedValue.id) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark")
                                            Text(NSLocalizedString("Read", comment: "already read badge"))
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                        .padding(.top, 2)
                                    }
                                }
                                Spacer()
                                
                                // NYTT: Snabbknapp för "Vill läsa" på varje rad – nu med "Välj utgåva"-flöde
                                Button {
                                    Task { await quickAddWantToReadFlow(book.wrappedValue) }
                                } label: {
                                    if rowAddInProgress == book.wrappedValue.id || isLoadingQuickAddEditions {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "bookmark")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(.accentColor)
                                .disabled(rowAddInProgress != nil || isLoadingQuickAddEditions)
                                .accessibilityLabel(Text(NSLocalizedString("Add to Want to Read", comment: "")))
                                
                                // Diskret chevron för att indikera detaljer
                                Image(systemName: "chevron.right")
                                    .foregroundColor(Color(UIColor.tertiaryLabel))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await openDetails(for: book.wrappedValue) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadTrending(force: false) }
        // Detaljvy för trending-bok
        .sheet(item: $selectedTrending) { item in
            TrendingBookDetailSheet(
                item: item,
                isWorking: trendingAddInProgress == item.id,
                onAddWithEdition: { chosenId in
                    Task { await addTrendingBook(item, editionId: chosenId) }
                }
            )
        }
        // NYTT: Detaljvy för sökträff – med genrer och moods och NU knappar för att lägga till
        .sheet(item: $selectedSearchDetail) { book in
            SearchResultDetailSheet(
                book: book,
                onAddComplete: { success in
                    if success {
                        onDone(true)
                        dismiss()
                    }
                }
            )
        }
        // NYTT: "Välj utgåva"-sheet för snabbknappen i sökresultatlistan
        .sheet(isPresented: $showingQuickAddEditionSheet) {
            if let pending = quickAddPendingBook {
                EditionSelectionSheet(
                    bookTitle: pending.title,
                    currentEditionId: quickAddSelectedEditionId,
                    editions: quickAddEditions,
                    onCancel: {
                        // Återställ state
                        quickAddPendingBook = nil
                        quickAddEditions = []
                        quickAddSelectedEditionId = nil
                    },
                    onSave: { chosenId in
                        // Kör själva "lägg till" efter att användaren valt utgåva
                        Task {
                            await addSearchResultToWantToRead(pending, editionId: chosenId)
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Cover helper
    private func cover(for book: HydratedBook) -> some View {
        let url = URL(string: book.image?.url ?? "")
        return Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color(UIColor.tertiarySystemFill)
                            ProgressView().scaleEffect(0.7)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_):
                        ZStack {
                            Color(UIColor.tertiarySystemFill)
                            Image(systemName: "book.closed").foregroundColor(.secondary)
                        }
                    @unknown default:
                        ZStack {
                            Color(UIColor.tertiarySystemFill)
                            Image(systemName: "book.closed").foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                ZStack {
                    Color(UIColor.tertiarySystemFill)
                    Image(systemName: "book.closed").foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 36, height: 52)
        .clipped()
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    // Overload to accept a Binding<HydratedBook> defensively (unwraps and forwards to the value-based helper)
    private func cover(for book: Binding<HydratedBook>) -> some View {
        cover(for: book.wrappedValue)
    }

    private func runSearch() async {
        errorMessage = nil
        let raw = query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let (titlePart, authorPart) = parseQuery(raw)
        
        isSearching = true
        let list = await HardcoverService.searchBooks(
            title: titlePart,
            author: authorPart?.isEmpty == false ? authorPart : nil
        )
        await MainActor.run {
            self.results = list
            self.isSearching = false
            if list.isEmpty {
                self.errorMessage = "No results. Try another search."
            }
        }
        // Efter att resultaten är satta, hämta vilka som redan är lästa (Finished)
        await refreshFinishedFlags()
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
    
    // NYTT: Open details for a search result
    private func openDetails(for book: HydratedBook) async {
        // Försök hämta en BookProgress med beskrivning (om möjligt) för en rik detaljvy
        let detail = await HardcoverService.fetchBookDetailsById(bookId: book.id, userBookId: nil, imageMaxPixel: 360, compression: 0.8)
        await MainActor.run {
            if let detail {
                selectedSearchDetail = detail
            } else {
                // Fallback: minimalt objekt om hämtning misslyckas
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
    
    private func loadTrending(force: Bool) async {
        guard force || trending.isEmpty else { return }
        await MainActor.run {
            trendingLoading = true
            trendingError = nil
        }
        // Endast månadens trending. Ingen fallback till all-time här.
        let list = await HardcoverService.fetchTrendingBooksMonthly(limit: 20, imageMaxPixel: 280, compression: 0.75)
        await MainActor.run {
            trendingLoading = false
            trending = list
            if list.isEmpty {
                trendingError = NSLocalizedString("Trending is not available right now.", comment: "")
            }
        }
    }
    
    private func addTrendingBook(_ item: HardcoverService.TrendingBook) async {
        await MainActor.run { trendingAddInProgress = item.id }
        
        // If user prefers to skip edition picker, add immediately (no edition)
        if skipEditionPickerOnAdd {
            let ok = await HardcoverService.addBookToWantToRead(bookId: item.id, editionId: nil)
            await MainActor.run {
                trendingAddInProgress = nil
                if ok {
                    onDone(true)
                    dismiss()
                } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
                }
            }
            return
        }
        
        // Otherwise, fetch editions and present picker when there are multiple
        await MainActor.run { isLoadingQuickAddEditions = true }
        let editions = await HardcoverService.fetchEditions(for: item.id)
        if editions.count <= 1 {
            let chosenId = editions.first?.id
            let ok = await HardcoverService.addBookToWantToRead(bookId: item.id, editionId: chosenId)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                trendingAddInProgress = nil
                if ok {
                    onDone(true)
                    dismiss()
                } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
                }
            }
        } else {
            await MainActor.run {
                quickAddPendingBook = HydratedBook(
                    id: item.id,
                    title: item.title,
                    contributions: nil,
                    image: nil
                )
                quickAddEditions = editions
                quickAddSelectedEditionId = editions.first?.id
                isLoadingQuickAddEditions = false
                showingQuickAddEditionSheet = true
                trendingAddInProgress = nil
            }
        }
    }
    
    // Overload used by detail sheet to add with a specific edition id
    private func addTrendingBook(_ item: HardcoverService.TrendingBook, editionId: Int?) async {
        await MainActor.run { trendingAddInProgress = item.id }
        let ok = await HardcoverService.addBookToWantToRead(bookId: item.id, editionId: editionId)
        await MainActor.run {
            trendingAddInProgress = nil
            if ok {
                onDone(true)
                dismiss()
            } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
            }
        }
    }
    
    // MARK: - NYTT: Snabb-add med editionsflöde
    private func quickAddWantToReadFlow(_ book: HydratedBook) async {
        // If user prefers to skip edition selection, add immediately with default (nil editionId)
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
        // Hämta utgåvor
        let editions = await HardcoverService.fetchEditions(for: book.id)
        // Om 0–1 utgåvor -> lägg till direkt
        if editions.count <= 1 {
            let eid = editions.first?.id
            await addSearchResultToWantToRead(book, editionId: eid)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                rowAddInProgress = nil
            }
            return
        }
        // Fler än en utgåva -> öppna väljare
        await MainActor.run {
            isLoadingQuickAddEditions = false
            rowAddInProgress = nil
            quickAddPendingBook = book
            quickAddEditions = editions
            quickAddSelectedEditionId = nil
            showingQuickAddEditionSheet = true
        }
    }
    
    // Ursprungliga snabb-add funktionen – nu återanvänd med explicit editionId
    private func addSearchResultToWantToRead(_ book: HydratedBook, editionId: Int?) async {
        await MainActor.run { rowAddInProgress = book.id }
        let ok = await HardcoverService.addBookToWantToRead(bookId: book.id, editionId: editionId)
        await MainActor.run {
            rowAddInProgress = nil
            if ok {
                onDone(true)
                dismiss()
            } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
            }
            // Stäng ev. quick-add-sheet state
            showingQuickAddEditionSheet = false
            quickAddPendingBook = nil
            quickAddEditions = []
            quickAddSelectedEditionId = nil
        }
    }
    
    // MARK: - Read flags loading
    private func refreshFinishedFlags() async {
        let ids = results.map { $0.id }
        guard !ids.isEmpty else {
            await MainActor.run { finishedBookIds = [] }
            return
        }
        let set = await queryFinishedBookIds(for: ids)
        await MainActor.run { finishedBookIds = set }
    }
    
    // Hämta aktuellt userId via GraphQL me
    private func fetchCurrentUserId() async -> Int? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let body = [
            "query": "{ me { id username } }"
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let meArr = dataDict["me"] as? [[String: Any]],
               let first = meArr.first,
               let id = first["id"] as? Int {
                return id
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // Batcha user_books för aktuella sökresultat och hämta de som är Finished (status_id == 3) FÖR INLOGGAD ANVÄNDARE.
    // Viktigt: matcha både direkt book_id och edition.book.id så vi inte missar poster där book_id är null.
    private func queryFinishedBookIds(for bookIds: [Int]) async -> Set<Int> {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let userId = await fetchCurrentUserId() else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($userId: Int!, $ids: [Int!]) {
          user_books(
            where: {
              user_id: { _eq: $userId },
              status_id: { _eq: 3 },
              _or: [
                { book_id: { _in: $ids } },
                { edition: { book: { id: { _in: $ids } } } }
              ]
            },
            limit: 500
          ) {
            book_id
            edition { book { id } }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId, "ids": bookIds]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return []
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]] {
                var out = Set<Int>()
                for row in rows {
                    if let bid = row["book_id"] as? Int {
                        out.insert(bid)
                        continue
                    }
                    if let ed = row["edition"] as? [String: Any],
                       let b = ed["book"] as? [String: Any],
                       let bid = b["id"] as? Int {
                        out.insert(bid)
                    }
                }
                return out
            }
        } catch {
            return []
        }
        return []
    }
    
    // MARK: Taggings-vägen (Genres) — added here to fix scope error
    private func queryBookGenresViaTaggings(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            taggings(limit: 200) { tag { tag tag_category { slug } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractGenresFromTaggings(first["taggings"])
            }
        } catch { return nil }
        return nil
    }
    
    private func queryUserBookGenresViaTaggings(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        // OBS: Hämtar endast via user_books.book.taggings (inte edition.book)
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first,
               let book = first["book"] as? [String: Any] {
                return extractGenresFromTaggings(book["taggings"])
            }
        } catch { return nil }
        return nil
    }
    
    private func extractGenresFromTaggings(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        var out: [String] = []
        for el in list {
            guard let row = el as? [String: Any],
                  let tag = row["tag"] as? [String: Any],
                  let name = tag["tag"] as? String,
                  let category = tag["tag_category"] as? [String: Any],
                  let slug = category["slug"] as? String else { continue }
            if slug.lowercased() == "genre" && !name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                out.append(name)
            }
        }
        return out.isEmpty ? nil : out
    }
    
    // MARK: Taggings-vägen (Moods)
    private func queryBookMoodsViaTaggings(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            taggings(limit: 200) { tag { tag tag_category { slug } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ books.taggings error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractMoodsFromTaggings(first["taggings"])
            }
        } catch {
            print("❌ books.taggings exception: \(error)")
            return nil
        }
        return nil
    }
    
    private func queryEditionBookMoodsViaTaggings(url: URL, editionId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          editions(where: { id: { _eq: $id }}) {
            id
            book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
          }
        }
        """
        let body = ["query": query, "variables": ["id": editionId]] as [String : Any]
   
