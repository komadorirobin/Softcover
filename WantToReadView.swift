import SwiftUI
import WidgetKit

struct WantToReadView: View {
    
    enum FilterType: String, CaseIterable {
        case all = "All"
        case upcoming = "Upcoming"
        case recent = "Recent"
    }
    
    @State private var items: [BookProgress] = []
    @State private var isLoading = true
    @State private var isWorkingId: String?
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @State private var selectedFilter: FilterType = .all
    @State private var notificationsEnabled: Bool = NotificationManager.isEnabled
    @State private var showNotificationsInfo = false
    @State private var isRequestingAuth = false
    @State private var mutedIds: Set<Int> = NotificationManager.mutedReleaseIds
    // NYTT: öppna bokdetaljer
    @State private var selectedBookForDetails: BookProgress?
    // NYTT: totalantal för rubriken
    @State private var totalWantToReadCount: Int?
    // NYTT: pending delete
    @State private var pendingDelete: BookProgress?
    // NYTT: cache för boknivåns medelbetyg (om editionAverage saknas)
    @State private var avgByBookId: [Int: Double] = [:]
    // NYTT: API settings
    @State private var showingApiSettings = false
    
    let onComplete: (Bool) -> Void
    
    init(onComplete: @escaping (Bool) -> Void) {
        self.onComplete = onComplete
    }
    
    // Rubrik (lokaliserad)
    private var titleText: String { NSLocalizedString("Want to Read", comment: "Title for Want to Read list") }
    
    // Liten infotext ovanför listan (lokaliserad)
    private var infoLineText: String? {
        let total = totalWantToReadCount ?? items.count
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            // “Showing N of X”
            return String.localizedStringWithFormat(
                NSLocalizedString("Showing %d of %d", comment: "Info line when filtering: showing N of X total"),
                filteredItems.count,
                total
            )
        } else {
            // “X in Want to Read”
            return String.localizedStringWithFormat(
                NSLocalizedString("%d in Want to Read", comment: "Info line above list: total count in Want to Read"),
                total
            )
        }
    }
    
    private func parseReleaseDate(_ dateString: String) -> Date? {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: dateString)
    }
    
    private func releaseDateView(for date: Date) -> some View {
        let formattedDate = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }()
        
        return HStack(spacing: 4) {
            Image(systemName: selectedFilter == .upcoming ? "calendar" : "clock")
                .font(.caption2)
            Text(formattedDate)
                .font(.caption2)
        }
        .foregroundColor(selectedFilter == .upcoming ? .blue : .green)
    }
    
    private var filteredItems: [BookProgress] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered = items
        
        // Filtrera efter text
        if !q.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                $0.author.localizedCaseInsensitiveContains(q)
            }
        }
        
        // Filtrera efter release date om inte "All"
        if selectedFilter != .all {
            let today = Calendar.current.startOfDay(for: Date())
            filtered = filtered.filter { book in
                guard let releaseDateString = book.releaseDate,
                      let releaseDate = parseReleaseDate(releaseDateString) else {
                    return false
                }
                
                switch selectedFilter {
                case .upcoming:
                    return releaseDate >= today
                case .recent:
                    return releaseDate < today
                case .all:
                    return true
                }
            }
            
            // Sortera efter release date
            filtered.sort { book1, book2 in
                guard let date1String = book1.releaseDate,
                      let date2String = book2.releaseDate,
                      let date1 = parseReleaseDate(date1String),
                      let date2 = parseReleaseDate(date2String) else {
                    return false
                }
                
                if selectedFilter == .upcoming {
                    return date1 < date2  // Närmaste först
                } else {
                    return date1 > date2  // Senaste först
                }
            }
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationView {
            contentView
            .navigationTitle(titleText)
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .task { await initialLoad() }
            .task { await loadTotalWantToReadCount() }
            .task { await syncNotificationState() }
            .refreshable { await reload() }
            .alert("Action failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $selectedBookForDetails) { book in
                InlineBookDetailView(
                    book: book,
                    onStart: { id in
                        Task { await startReading(userBookId: id) }
                    },
                    onEditionChanged: {
                        Task {
                            await reload()
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    },
                    onRemove: { id in
                        Task { await removeWantToRead(userBookId: id) }
                    }
                )
            }
            .sheet(isPresented: $showingApiSettings) {
                ApiKeySettingsView { _ in
                    Task {
                        await reload()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
            .confirmationDialog(
                NSLocalizedString("Remove from Want to Read?", comment: "Confirm removal title"),
                isPresented: .constant(pendingDelete != nil),
                presenting: pendingDelete
            ) { book in
                Button(NSLocalizedString("Remove", comment: "Confirm removal button"), role: .destructive) {
                    if let id = book.userBookId {
                        Task { await removeWantToRead(userBookId: id) }
                    }
                    pendingDelete = nil
                }
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                    pendingDelete = nil
                }
            } message: { book in
                Text(book.title)
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            if isLoading && items.isEmpty {
                loadingView
            } else if let errorMessage, items.isEmpty {
                errorView(message: errorMessage)
            } else if filteredItems.isEmpty {
                emptyView
            } else {
                listView
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.3)
            Text("Loading Want to Read…")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Failed to load list")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await reload() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No books in Want to Read")
                .font(.headline)
            Text("Add books to your Want to Read list on Hardcover to see them here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var listView: some View {
        VStack(spacing: 0) {
            // Filter picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(FilterType.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            List {
                        Section {
                            // Liten infotext överst
                            if let info = infoLineText {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.secondary)
                                    Text(info)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer(minLength: 0)
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                            }
                            
                            ForEach(filteredItems) { book in
                            HStack(spacing: 12) {
                                cover(for: book)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)
                                    Text(book.author)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    
                                    // NYTT: Medelbetyg – samma placering som i detaljvyerna, direkt under författare.
                                    if let avg = (book.editionAverageRating ?? (book.bookId.flatMap { avgByBookId[$0] })) {
                                        HStack(spacing: 8) {
                                            RowReadOnlyStars(rating: avg)
                                            Text(String(format: NSLocalizedString("Average %.1f", comment: ""), avg))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    // Visa release date om filtrerat på Upcoming/Recent
                                    if selectedFilter != .all, 
                                       let releaseDateString = book.releaseDate, 
                                       let releaseDate = parseReleaseDate(releaseDateString) {
                                        releaseDateView(for: releaseDate)
                                    }
                                    
                                    if book.totalPages > 0 {
                                        Text("\(book.totalPages) pages")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    // Visa bell-ikon för upcoming releases om notiser är aktiverade
                                    if selectedFilter == .upcoming, 
                                       notificationsEnabled,
                                       let bookId = book.bookId {
                                        Button {
                                            Task { await toggleMute(for: bookId) }
                                        } label: {
                                            let isMuted = mutedIds.contains(bookId)
                                            Image(systemName: isMuted ? "bell.slash" : "bell.badge")
                                                .foregroundColor(isMuted ? .secondary : .accentColor)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(
                                            mutedIds.contains(bookId)
                                            ? Text(NSLocalizedString("Notifications muted for this book", comment: ""))
                                            : Text(NSLocalizedString("Notifications enabled for this book", comment: ""))
                                        )
                                    }
                                    
                                    if let id = book.userBookId {
                                        if isWorkingId == book.id {
                                            ProgressView()
                                        } else {
                                            Button {
                                                Task { await startReading(userBookId: id) }
                                            } label: {
                                                // Icke-brytande mellanrum för att undvika radbrytning mellan “Läs” och “nu”
                                                Label("Läs\u{00A0}nu", systemImage: "book.fill")
                                                    .lineLimit(1)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .tint(.accentColor)
                                            .accessibilityLabel("Läs nu")
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle()) // gör hela raden klickbar för onTapGesture
                            .onTapGesture {
                                selectedBookForDetails = book
                            }
                            // Långtryck: contextmeny med Ta bort
                            .contextMenu {
                                if let _ = book.userBookId {
                                    Button(role: .destructive) {
                                        pendingDelete = book
                                    } label: {
                                        Label("Remove from Want to Read", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } footer: {
                        if selectedFilter == .upcoming && notificationsEnabled {
                            Text(NSLocalizedString("Tap the bell icon to mute or unmute release notifications for individual books. Notifications are sent at 9:00 AM on the release date.", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }  // List
                .listStyle(.plain)
            }  // VStack
        }  // End of listView
    
    private func cover(for book: BookProgress) -> some View {
        Group {
            if let data = book.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "book.closed")
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(width: 44, height: 64)
        .clipped()
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    
    private func initialLoad() async {
        if items.isEmpty {
            await reload()
        }
    }
    
    private func reload() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        let list = await HardcoverService.fetchWantToRead(limit: 200)
        await MainActor.run {
            items = list
            isLoading = false
        }
        // NYTT: uppdatera totalantal efter reload (parallellt hade redan körts i .task, men uppdatera här också)
        await loadTotalWantToReadCount()
        // NYTT: hämta medelbetyg (boknivå) för rader som saknar editionAverageRating
        await populateAverageRatings()
    }
    
    // NYTT: Hämta saknade medelbetyg på boknivå
    private func populateAverageRatings() async {
        guard !HardcoverConfig.apiKey.isEmpty else { return }
        let candidates = items.compactMap { item -> Int? in
            guard let bid = item.bookId else { return nil }
            if item.editionAverageRating != nil { return nil }
            if avgByBookId[bid] != nil { return nil }
            return bid
        }
        guard !candidates.isEmpty else { return }
        // Hämta sekventiellt (enkelt och snällt mot API:t)
        for bid in candidates {
            if let avg = await fetchBookAverageRating(bookId: bid) {
                await MainActor.run {
                    avgByBookId[bid] = avg
                }
            }
        }
    }
    
    // NYTT: GraphQL-hjälpare för medelbetyg på boknivå (samma som i detaljvyerna)
    private func fetchBookAverageRating(bookId: Int) async -> Double? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            rating
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["id": bookId]
        ]
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
                return first["rating"] as? Double
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // NYTT: liten read-only stjärnvy för raden
    private struct RowReadOnlyStars: View {
        let rating: Double // 0…5
        var body: some View {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let threshold = Double(i) + 1.0
                    if rating >= threshold {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                    } else if rating + 0.5 >= threshold {
                        Image(systemName: "star.leadinghalf.filled")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "star")
                            .foregroundColor(.orange.opacity(0.35))
                    }
                }
            }
            .font(.caption)
            .accessibilityLabel("Rating")
            .accessibilityValue("\(rating, specifier: "%.1f") of 5")
        }
    }
    
    // NYTT: hämta totala antalet i "Want to Read" för den inloggade användaren via user_id
    private func loadTotalWantToReadCount() async {
        guard !HardcoverConfig.apiKey.isEmpty else { return }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return }
        
        // 1) Hämta user_id via me
        func fetchCurrentUserId() async -> Int? {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            let body = "{ \"query\": \"{ me { id username } }\" }"
            req.httpBody = body.data(using: .utf8)
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                    return nil
                }
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
        
        guard let userId = await fetchCurrentUserId() else { return }
        
        // 2) Aggregatfråga på user_books via user_id + status_id == 1
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($userId: Int!) {
          user_books_aggregate(
            where: {
              status_id: { _eq: 1 },
              user_id: { _eq: $userId }
            }
          ) {
            aggregate { count }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let agg = dataDict["user_books_aggregate"] as? [String: Any],
               let aggregate = agg["aggregate"] as? [String: Any],
               let count = aggregate["count"] as? Int {
                await MainActor.run {
                    self.totalWantToReadCount = count
                }
            }
        } catch {
            // Tyst felhantering; behåll tidigare värde
        }
    }
    
    private func startReading(userBookId: Int) async {
        // Prevent duplicate work on the same userBookId
        guard isWorkingId != "\(userBookId)" else { return }
        await MainActor.run { isWorkingId = "\(userBookId)" }
        let ok = await HardcoverService.updateUserBookStatus(userBookId: userBookId, statusId: 2)
        await MainActor.run {
            isWorkingId = nil
            if ok {
                WidgetCenter.shared.reloadAllTimelines()
                onComplete(true)
            } else {
                errorMessage = "Could not start reading. Please try again."
            }
        }
    }
    
    // Ta bort från Vill läsa (via långtryck/contextmeny eller från detaljvyn)
    private func removeWantToRead(userBookId: Int) async {
        guard isWorkingId == nil else { return }
        await MainActor.run { isWorkingId = "\(userBookId)" }
        let ok = await HardcoverService.deleteUserBook(userBookId: userBookId)
        await MainActor.run {
            isWorkingId = nil
            if ok {
                // Stäng ev. öppen detaljvy för samma bok
                if let sel = selectedBookForDetails, sel.userBookId == userBookId {
                    selectedBookForDetails = nil
                }
                // Ta bort från listan
                items.removeAll { $0.userBookId == userBookId }
                // Uppdatera totalräknaren om vi har den
                if let total = totalWantToReadCount, total > 0 {
                    totalWantToReadCount = max(0, total - 1)
                }
                pendingDelete = nil
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                errorMessage = NSLocalizedString("Failed to remove the book. Please try again.", comment: "")
            }
        }
    }
    
    // MARK: - Notification helpers
    private func syncNotificationState() async {
        await MainActor.run {
            notificationsEnabled = NotificationManager.isEnabled
            mutedIds = NotificationManager.mutedReleaseIds
        }
    }
    
    private func toggleMute(for bookId: Int) async {
        let currentlyMuted = mutedIds.contains(bookId)
        await MainActor.run {
            if currentlyMuted {
                mutedIds.remove(bookId)
            } else {
                mutedIds.insert(bookId)
            }
        }
        NotificationManager.setMuted(!currentlyMuted, for: bookId)
        
        if currentlyMuted {
            // Unmuted -> schedule notification if we have release date
            if let book = items.first(where: { $0.bookId == bookId }),
               let releaseDateString = book.releaseDate,
               let releaseDate = parseReleaseDate(releaseDateString) {
                let release = makeUpcomingRelease(from: book, releaseDate: releaseDate)
                await NotificationManager.scheduleReleaseNotification(for: release)
            }
        } else {
            // Muted -> cancel notification
            await NotificationManager.removeNotification(for: bookId)
        }
    }
    
    private func makeUpcomingRelease(from book: BookProgress, releaseDate: Date) -> HardcoverService.UpcomingRelease {
        return HardcoverService.UpcomingRelease(
            id: book.bookId ?? 0,
            bookId: book.bookId,
            title: book.title,
            author: book.author,
            releaseDate: releaseDate,
            coverImageData: book.coverImageData
        )
    }
}

// MARK: - InlineBookDetailView
// Lightweight inline detail sheet to avoid cross-target dependency on BookDetailView
private struct InlineBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let book: BookProgress
    let onStart: (Int) -> Void
    // NYTT: callback till förälder när utgåva har bytts
    let onEditionChanged: () -> Void
    // NYTT: callback för att ta bort från vill läsa
    let onRemove: (Int) -> Void
    
    // Reviews state
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @State private var reviews: [HardcoverService.PublicReview] = []
    @State private var reviewsPage = 0
    private let reviewsPageSize = 10
    @State private var canLoadMoreReviews = true
    
    // NYTT: visa utgåveväljaren
    @State private var showingEditionPicker = false
    
    // NYTT: Genres & Moods state
    @State private var genres: [String] = []
    @State private var isLoadingGenres = false
    @State private var moods: [String] = []
    @State private var isLoadingMoods = false
    
    // NYTT: ta bort-bekräftelse
    @State private var showDeleteConfirm = false
    
    // NYTT: medelbetyg fallback (boknivå)
    @State private var averageRating: Double?
    
    // NYTT: Beskrivning (fallbackhämtning)
    @State private var descriptionText: String?
    @State private var isLoadingDescription = false
    
    private var percentText: String? {
        guard book.progress > 0 else { return nil }
        return "\(Int(book.progress * 100))%"
    }
    
    private var pagesInfo: String {
        if book.totalPages > 0 && book.currentPage > 0 {
            return "Page \(book.currentPage) of \(book.totalPages)"
        } else if book.currentPage > 0 {
            return "Page \(book.currentPage)"
        } else if book.totalPages > 0 {
            return "\(book.totalPages) pages"
        } else {
            return "No progress information"
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        if let data = book.coverImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 90, height: 130)
                                .clipped()
                                .cornerRadius(8)
                                .shadow(radius: 3)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(width: 90, height: 130)
                                .overlay(
                                    Image(systemName: "book.closed")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .lineLimit(3)
                                .lineLimit(3)
                            Text(book.author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            // NYTT: Average rating i headern – samma placering som i BookDetailView
                            if let avg = (book.editionAverageRating ?? averageRating) {
                                HStack(spacing: 8) {
                                    InlineReadOnlyStars(rating: avg)
                                    Text(String(format: NSLocalizedString("Average %.1f", comment: ""), avg))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // GENRES: direkt under författarnamnet, i headern
                            if !genres.isEmpty {
                                WrapChipsView(items: genres)
                                    .padding(.top, 2)
                            } else if isLoadingGenres {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text(NSLocalizedString("Loading genres…", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 2)
                            }
                            
                            // Separator if both genres and moods exist
                            if !genres.isEmpty && !moods.isEmpty {
                                Divider()
                                    .padding(.vertical, 2)
                            }
                            
                            // MOODS
                            if !moods.isEmpty {
                                WrapChipsView(items: moods)
                            } else if isLoadingMoods {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text(NSLocalizedString("Loading moods…", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Snabbåtgärder: Läs nu och Byt utgåva (Omdöme borttagen)
                    if let userBookId = book.userBookId {
                        HStack(spacing: 12) {
                            Button {
                                onStart(userBookId)
                            } label: {
                                Label("Läs\u{00A0}nu", systemImage: "book.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
                            .accessibilityLabel("Läs nu")
                            
                            Button {
                                showingEditionPicker = true
                            } label: {
                                Label("Change Edition", systemImage: "books.vertical.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Change Edition")
                        }
                    }
                    
                    // Progress (utan progress-bar)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(pagesInfo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if let pct = percentText {
                                Text(pct)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    // Description (boknivå)
                    if let desc = normalizedDescription(descriptionText ?? book.bookDescription) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            Text(desc)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    } else if isLoadingDescription {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.9)
                            Text(NSLocalizedString("Loading description…", comment: "Loading state for description"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Reviews section
                    if let bookId = book.bookId {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Reviews")
                                    .font(.headline)
                                Spacer()
                                if isLoadingReviews {
                                    ProgressView().scaleEffect(0.9)
                                }
                            }
                            
                            if let err = reviewsError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if reviews.isEmpty && !isLoadingReviews {
                                Text("No reviews found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(reviews) { r in
                                        InlineReviewRow(review: r)
                                    }
                                    if canLoadMoreReviews {
                                        HStack {
                                            Spacer()
                                            Button {
                                                Task { await loadMoreReviews(for: bookId) }
                                            } label: {
                                                if isLoadingReviews {
                                                    ProgressView().scaleEffect(0.9)
                                                } else {
                                                    Text("Load more")
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            Spacer()
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                        .task {
                            if reviewsPage == 0 && reviews.isEmpty {
                                await reloadReviews(for: bookId)
                            }
                        }
                    }
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 6) {
                        if let eid = book.editionId {
                            Label("Edition ID: \(eid)", systemImage: "books.vertical.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let bid = book.bookId {
                            Label("Book ID: \(bid)", systemImage: "number")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let uid = book.userBookId {
                            Label("User Book ID: \(uid)", systemImage: "person.text.rectangle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let _ = book.userBookId {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(NSLocalizedString("Remove from Want to Read", comment: ""))
                    }
                }
            }
            // Edition Picker Sheet
            .sheet(isPresented: $showingEditionPicker) {
                EditionPickerView(book: book) { success in
                    if success {
                        onEditionChanged()
                        WidgetCenter.shared.reloadAllTimelines()
                        print("✅ Widget timelines reloaded after edition change from InlineBookDetailView.")
                    }
                }
            }
            // Hämta genres + moods när vyn laddas (via bookId/editionId/userBookId)
            .task { await reloadGenres() }
            // Hämta medelbetyg på boknivå om editionsbetyg saknas
            .task {
                if averageRating == nil, book.editionAverageRating == nil, let id = book.bookId {
                    let avg = await fetchBookAverageRating(bookId: id)
                    await MainActor.run { averageRating = avg }
                }
            }
            // Hämta beskrivning om den saknas i modellen
            .task {
                if descriptionText == nil, (book.bookDescription == nil || book.bookDescription?.isEmpty == true),
                   let id = book.bookId {
                    await MainActor.run { isLoadingDescription = true }
                    let fetched = await fetchBookDescription(bookId: id)
                    await MainActor.run {
                        descriptionText = fetched
                        isLoadingDescription = false
                    }
                }
            }
            // Bekräfta borttagning
            .confirmationDialog(
                NSLocalizedString("Remove from Want to Read?", comment: "Confirm removal title"),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                if let ubid = book.userBookId {
                    Button(NSLocalizedString("Remove", comment: "Confirm remove"), role: .destructive) {
                        onRemove(ubid)
                        dismiss()
                    }
                }
                Button(NSLocalizedString("Cancel", comment: "Cancel remove"), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("This book will be removed from your Want to Read list.", comment: "Remove explanation"))
            }
        }
    }
    
    private func reloadGenres() async {
        // Load both genres and moods in parallel
        await MainActor.run {
            if genres.isEmpty { isLoadingGenres = true }
            if moods.isEmpty { isLoadingMoods = true }
        }
        // Genrer: hämta endast från huvudboken (inte via editions)
        async let g = fetchGenresPreferred(bookId: book.bookId, editionId: book.editionId, userBookId: book.userBookId)
        // Moods: oförändrat
        async let m = fetchMoodsPreferred(bookId: book.bookId, editionId: book.editionId, userBookId: book.userBookId)
        let (gList, mList) = await (g, m)
        await MainActor.run {
            self.genres = gList
            self.moods = mList
            self.isLoadingGenres = false
            self.isLoadingMoods = false
        }
    }
    
    // Enkel sanering av HTML-taggar
    private func normalizedDescription(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let withoutTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return withoutTags.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Reviews loading
    private func reloadReviews(for bookId: Int) async {
        await MainActor.run {
            isLoadingReviews = true
            reviewsError = nil
            reviewsPage = 0
            canLoadMoreReviews = true
            reviews = []
        }
        let list = await HardcoverService.fetchPublicReviewsForBook(bookId: bookId, limit: reviewsPageSize, offset: 0)
        await MainActor.run {
            isLoadingReviews = false
            reviews = list
            canLoadMoreReviews = list.count == reviewsPageSize
            reviewsPage = 1
        }
    }
    
    private func loadMoreReviews(for bookId: Int) async {
        guard !isLoadingReviews, canLoadMoreReviews else { return }
        await MainActor.run { isLoadingReviews = true }
        let offset = reviewsPage * reviewsPageSize
               let list = await HardcoverService.fetchPublicReviewsForBook(bookId: bookId, limit: reviewsPageSize, offset: offset)
        await MainActor.run {
            isLoadingReviews = false
            if list.isEmpty {
                canLoadMoreReviews = false
            } else {
                reviews.append(contentsOf: list)
                reviewsPage += 1
                if list.count < reviewsPageSize { canLoadMoreReviews = false }
            }
        }
    }
    
    // MARK: - Genres & Moods loading (taggings first, then cached_tags)
    // GENRES: Endast från huvudboken (inte via editions)
    private func fetchGenresPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        // 1) Försök via taggings (bok)
        if let bid = bookId {
            if let arr = await queryBookGenresViaTaggings(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // 2) Fallback via taggings (user_book -> bok) [OBS: inte via edition.book]
        if let ubid = userBookId {
            if let arr = await queryUserBookGenresViaTaggings(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        
        // 3) Fallback via cached_tags (bok)
        if let bid = bookId {
            if let arr = await queryBookCachedGenres(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // 4) Fallback via cached_tags (user_book -> bok) [OBS: inte via edition.book]
        if let ubid = userBookId {
            if let arr = await queryUserBookCachedGenres(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        
        return []
    }
    
    private func fetchMoodsPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        // 1) Taggings path
        if let bid = bookId {
            if let arr = await queryBookMoodsViaTaggings(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await queryEditionBookMoodsViaTaggings(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookMoodsViaTaggings(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        
        // 2) cached_tags path
        if let bid = bookId {
            if let arr = await queryBookCachedMoods(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await queryEditionBookCachedMoods(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookCachedMoods(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        return []
    }
    
    // MARK: Taggings-vägen (Genres)
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
            if slug.lowercased() == "genre" && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                print("❌ books.taggings moods error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractMoodsFromTaggings(first["taggings"])
            }
        } catch {
            print("❌ books.taggings moods exception: \(error)")
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
        let body: [String: Any] = ["query": query, "variables": ["id": editionId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ edition.book.taggings moods error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let editions = dataDict["editions"] as? [[String: Any]],
               let first = editions.first,
               let book = first["book"] as? [String: Any] {
                return extractMoodsFromTaggings(book["taggings"])
            }
        } catch {
            print("❌ edition.book.taggings moods exception: \(error)")
            return nil
        }
        return nil
    }
    
    private func queryUserBookMoodsViaTaggings(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
            edition { id book { id taggings(limit: 200) { tag { tag tag_category { slug } } } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ user_books moods error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first {
                if let book = first["book"] as? [String: Any],
                   let arr = extractMoodsFromTaggings(book["taggings"]),
                   !arr.isEmpty { return arr }
                if let ed = first["edition"] as? [String: Any],
                   let b = ed["book"] as? [String: Any],
                   let arr = extractMoodsFromTaggings(b["taggings"]),
                   !arr.isEmpty { return arr }
            }
        } catch {
            print("❌ user_books moods exception: \(error)")
            return nil
        }
        return nil
    }
    
    private func extractMoodsFromTaggings(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        var out: [String] = []
        for el in list {
            guard let row = el as? [String: Any],
                  let tag = row["tag"] as? [String: Any],
                  let name = tag["tag"] as? String,
                  let category = tag["tag_category"] as? [String: Any],
                  let slug = category["slug"] as? String else { continue }
            if slug.lowercased() == "mood" && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(name)
            }
        }
        return out.isEmpty ? nil : out
    }
    
    // MARK: cached_tags-vägen (Genres) parser already above in BookDetailView; we keep separate here for locality if needed.
    private func extractGenres(fromCachedTags value: Any?) -> [String]? {
        guard let value else { return nil }
        
        func isGenreContext(_ v: Any?) -> Bool {
            guard let s = (v as? String)?.lowercased() else { return false }
            return s == "genre" || s == "genres"
        }
        
        func nameFrom(_ dict: [String: Any]) -> String? {
            for key in ["name", "label", "title", "tag"] {
                if let s = dict[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
            return nil
        }
        
        if let arr = value as? [String] {
            return arr
        }
        if let arrAny = value as? [Any] {
            var out: [String] = []
            for el in arrAny {
                if let s = el as? String { out.append(s); continue }
                if let d = el as? [String: Any] {
                    if isGenreContext(d["context"]) || isGenreContext(d["type"]) || isGenreContext(d["kind"]) || isGenreContext(d["category"]) || isGenreContext(d["group"]) {
                        if let n = nameFrom(d) { out.append(n) }
                        continue
                    }
                    if let t = d["tag"] as? [String: Any] {
                        if isGenreContext(t["context"]) || isGenreContext(t["type"]) || isGenreContext(t["kind"]) || isGenreContext(t["category"]) || isGenreContext(t["group"]) {
                            if let n = nameFrom(t) { out.append(n) }
                            continue
                        }
                    }
                }
            }
            return out.isEmpty ? nil : out
        }
        if let dict = value as? [String: Any] {
            if let g = dict["genres"] {
                if let arr = g as? [String] { return arr }
                if let arrAny = g as? [Any] {
                    var out: [String] = []
                    for el in arrAny {
                        if let s = el as? String { out.append(s); continue }
                        if let d = el as? [String: Any] {
                            if let n = nameFrom(d) { out.append(n); continue }
                            if let t = d["tag"] as? [String: Any], let n = nameFrom(t) { out.append(n); continue }
                        }
                    }
                    return out.isEmpty ? nil : out
                }
            }
            if let tags = dict["tags"] as? [Any] {
                var out: [String] = []
                for el in tags {
                    if let d = el as? [String: Any] {
                        if isGenreContext(d["context"]) || isGenreContext(d["type"]) || isGenreContext(d["kind"]) || isGenreContext(d["category"]) || isGenreContext(d["group"]) {
                            if let n = nameFrom(d) { out.append(n) }
                            continue
                        }
                        if let t = d["tag"] as? [String: Any] {
                            if isGenreContext(t["context"]) || isGenreContext(t["type"]) || isGenreContext(t["kind"]) || isGenreContext(t["category"]) || isGenreContext(t["group"]) {
                                if let n = nameFrom(t) { out.append(n) }
                                continue
                            }
                        }
                    }
                }
                return out.isEmpty ? nil : out
            }
        }
        return nil
    }
    
    // MARK: cached_tags-vägen (Moods)
    private func extractMoods(fromCachedTags value: Any?) -> [String]? {
        guard let value else { return nil }
        
        func isMoodContext(_ v: Any?) -> Bool {
            guard let s = (v as? String)?.lowercased() else { return false }
            return s == "mood" || s == "moods"
        }
        
        func nameFrom(_ dict: [String: Any]) -> String? {
            for key in ["name", "label", "title", "tag"] {
                if let s = dict[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
            return nil
        }
        
        if let arr = value as? [String] {
            return arr
        }
        if let arrAny = value as? [Any] {
            var out: [String] = []
            for el in arrAny {
                if let s = el as? String { out.append(s); continue }
                if let d = el as? [String: Any] {
                    if isMoodContext(d["context"]) || isMoodContext(d["type"]) || isMoodContext(d["kind"]) || isMoodContext(d["category"]) || isMoodContext(d["group"]) {
                        if let n = nameFrom(d) { out.append(n) }
                        continue
                    }
                    if let t = d["tag"] as? [String: Any] {
                        if isMoodContext(t["context"]) || isMoodContext(t["type"]) || isMoodContext(t["kind"]) || isMoodContext(t["category"]) || isMoodContext(t["group"]) {
                            if let n = nameFrom(t) { out.append(n) }
                            continue
                        }
                    }
                }
            }
            return out.isEmpty ? nil : out
        }
        if let dict = value as? [String: Any] {
            if let m = dict["moods"] {
                if let arr = m as? [String] { return arr }
                if let arrAny = m as? [Any] {
                    var out: [String] = []
                    for el in arrAny {
                        if let s = el as? String { out.append(s); continue }
                        if let d = el as? [String: Any] {
                            if let n = nameFrom(d) { out.append(n); continue }
                            if let t = d["tag"] as? [String: Any], let n = nameFrom(t) { out.append(n); continue }
                        }
                    }
                    return out.isEmpty ? nil : out
                }
            }
            if let tags = dict["tags"] as? [Any] {
                var out: [String] = []
                for el in tags {
                    if let d = el as? [String: Any] {
                        if isMoodContext(d["context"]) || isMoodContext(d["type"]) || isMoodContext(d["kind"]) || isMoodContext(d["category"]) || isMoodContext(d["group"]) {
                            if let n = nameFrom(d) { out.append(n) }
                            continue
                        }
                        if let t = d["tag"] as? [String: Any] {
                            if isMoodContext(t["context"]) || isMoodContext(t["type"]) || isMoodContext(t["kind"]) || isMoodContext(t["category"]) || isMoodContext(t["group"]) {
                                if let n = nameFrom(t) { out.append(n) }
                                continue
                            }
                        }
                    }
                }
                return out.isEmpty ? nil : out
            }
        }
        return nil
    }
    
    // MARK: cached_tags-vägen (Genres) – missing helpers added
    private func queryBookCachedGenres(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            cached_tags
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
                return extractGenres(fromCachedTags: first["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    private func queryUserBookCachedGenres(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        // OBS: Hämtar endast via user_books.book.cached_tags (inte edition.book)
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
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
                return extractGenres(fromCachedTags: book["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    // MARK: cached_tags-vägen (Moods) – missing helpers added
    private func queryBookCachedMoods(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            cached_tags
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
                return extractMoods(fromCachedTags: first["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    private func queryEditionBookCachedMoods(url: URL, editionId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          editions(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
          }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": editionId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let editions = dataDict["editions"] as? [[String: Any]],
               let first = editions.first,
               let book = first["book"] as? [String: Any] {
                return extractMoods(fromCachedTags: book["cached_tags"])
            }
        } catch { return nil }
        return nil
    }
    
    private func queryUserBookCachedMoods(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
            edition { id book { id cached_tags } }
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
               let first = rows.first {
                if let book = first["book"] as? [String: Any],
                   let arr = extractMoods(fromCachedTags: book["cached_tags"]),
                   !arr.isEmpty { return arr }
                if let ed = first["edition"] as? [String: Any],
                   let b = ed["book"] as? [String: Any],
                   let arr = extractMoods(fromCachedTags: b["cached_tags"]),
                   !arr.isEmpty { return arr }
            }
        } catch { return nil }
        return nil
    }
    
    // Hämta medelbetyg på boknivå (fallback)
    private func fetchBookAverageRating(bookId: Int) async -> Double? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            rating
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["id": bookId]
        ]
        
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
                return first["rating"] as? Double
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // Hämta beskrivning på boknivå
    private func fetchBookDescription(bookId: Int) async -> String? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            description
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["id": bookId]
        ]
        
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
                return first["description"] as? String
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // Enkel read-only stjärnvy för betyg
    private struct InlineReadOnlyStars: View {
        let rating: Double // 0…5
        var body: some View {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let threshold = Double(i) + 1.0
                    if rating >= threshold {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                    } else if rating + 0.5 >= threshold {
                        // Använd SF-symbolen för halva stjärnor (tillgänglig i moderna system)
                        Image(systemName: "star.leadinghalf.filled")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "star")
                            .foregroundColor(.orange.opacity(0.35))
                    }
                }
            }
            .font(.caption)
            .accessibilityLabel("Rating")
            .accessibilityValue("\(rating, specifier: "%.1f") of 5")
        }
    }
    
    // Recensionsrad för inline-detaljvyn
    private struct InlineReviewRow: View {
        let review: HardcoverService.PublicReview
        
        @State private var likesCount: Int
        @State private var userHasLiked: Bool
        @State private var isLiking: Bool = false
        
        init(review: HardcoverService.PublicReview) {
            self.review = review
            _likesCount = State(initialValue: review.likesCount)
            _userHasLiked = State(initialValue: review.userHasLiked)
        }
        
        private func formattedDate(_ d: Date?) -> String {
            guard let d else { return "" }
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: d)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let name = review.username, !name.isEmpty {
                        Text("@\(name)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    } else {
                        Text("Review")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    Text(formattedDate(review.reviewedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let r = review.rating {
                    InlineReadOnlyStars(rating: r)
                }
                if let text = review.text, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        Task { await toggleLike() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: userHasLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .imageScale(.small)
                            Text("\(likesCount)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isLiking)
                    .accessibilityLabel(userHasLiked ? Text("Unlike review") : Text("Like review"))
                    .accessibilityValue(Text("\(likesCount)"))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
        
        private func toggleLike() async {
            guard !isLiking else { return }
            let wasLiked = userHasLiked
            let newLikeState = !wasLiked
            
            await MainActor.run {
                isLiking = true
                // Optimistic update
                userHasLiked = newLikeState
                if newLikeState {
                    likesCount += 1
                } else {
                    likesCount = max(0, likesCount - 1)
                }
            }
            
            // Local helper to avoid cross-target issues with HardcoverService extension
            let result = await setLike(likeableId: review.id, like: newLikeState, likeableType: "UserBook")
            
            await MainActor.run {
                if let result {
                    // Update with confirmed state from server
                    likesCount = max(0, result.likesCount)
                    userHasLiked = result.didLike
#if os(iOS) && !targetEnvironment(macCatalyst)
                    if userHasLiked {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
#endif
                } else {
                    // Rollback on failure
                    userHasLiked = wasLiked
                    if wasLiked {
                        likesCount += 1
                    } else {
                        likesCount = max(0, likesCount - 1)
                    }
                }
                isLiking = false
            }
        }
        
        // MARK: - Local like helpers (mirrors HardcoverService+LikesToggle)
        private func setLike(likeableId: Int, like: Bool, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
            if like {
                return await upsertLike(likeableId: likeableId, likeableType: likeableType)
            } else {
                return await deleteLike(likeableId: likeableId, likeableType: likeableType)
            }
        }
        
        private func upsertLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
            guard !HardcoverConfig.apiKey.isEmpty else { return nil }
            guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            let mutation = """
            mutation UpsertLike($likeableId: Int!, $likeableType: String!) {
              likeResult: upsert_like(likeable_id: $likeableId, likeable_type: $likeableType) {
                likesCount: likes_count
                __typename
              }
            }
            """
            let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
            let body: [String: Any] = ["query": mutation, "variables": vars]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (root["errors"] as? [[String: Any]])?.isEmpty != false,
                      let dataDict = root["data"] as? [String: Any],
                      let likeResult = dataDict["likeResult"] as? [String: Any],
                      let likesCount = likeResult["likesCount"] as? Int else { return nil }
                return (max(0, likesCount), true)
            } catch { return nil }
        }
        
        private func deleteLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
            guard !HardcoverConfig.apiKey.isEmpty else { return nil }
            guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
            let mutation = """
            mutation DeleteLike($likeableId: Int!, $likeableType: String!) {
              likeResult: delete_like(likeable_id: $likeableId, likeable_type: $likeableType) {
                likesCount: likes_count
                __typename
              }
            }
            """
            let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
            let body: [String: Any] = ["query": mutation, "variables": vars]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (root["errors"] as? [[String: Any]])?.isEmpty != false,
                      let dataDict = root["data"] as? [String: Any],
                      let likeResult = dataDict["likeResult"] as? [String: Any],
                      let likesCount = likeResult["likesCount"] as? Int else { return nil }
                return (max(0, likesCount), false)
            } catch { return nil }
        }
    }
    
    // MARK: - Flow layout (samma som i BookDetailView)
    private struct ChipsFlowLayout: Layout {
        var spacing: CGFloat = 6
        var rowSpacing: CGFloat = 6
        
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for sub in subviews {
                let size = sub.sizeThatFits(.unspecified)
                if x > 0 && x + size.width > maxWidth {
                    // ny rad
                    x = 0
                    y += rowSpacing + rowHeight
                    rowHeight = 0
                }
                rowHeight = max(rowHeight, size.height)
                x += size.width + (x > 0 ? spacing : 0)
            }
            return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
        }
        
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            var x: CGFloat = bounds.minX
            var y: CGFloat = bounds.minY
            var rowHeight: CGFloat = 0
            
            for sub in subviews {
                let size = sub.sizeThatFits(.unspecified)
                if x > bounds.minX && x + size.width > bounds.maxX {
                    // ny rad
                    x = bounds.minX
                    y += rowSpacing + rowHeight
                    rowHeight = 0
                }
                sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
    }
    
    // Wrap chips for genres and moods – använder ChipsFlowLayout (stabil höjd)
    private struct WrapChipsView: View {
        let items: [String]
        var body: some View {
            ChipsFlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(items, id: \.self) { text in
                    Text(text)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

#Preview { SearchBooksView { _ in } }
