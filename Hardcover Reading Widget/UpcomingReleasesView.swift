import SwiftUI

struct UpcomingReleasesView: View {
    @State private var releases: [HardcoverService.UpcomingRelease] = []
    @State private var recentReleases: [HardcoverService.UpcomingRelease] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    // NYTT: öppna bokdetaljer
    @State private var selectedBookForDetails: BookProgress?
    // NYTT: notiser
    @State private var notificationsEnabled: Bool = NotificationManager.isEnabled
    @State private var isRequestingAuth = false
    // NYTT: informationsruta innan vi ber om tillstånd
    @State private var showNotificationsInfo = false
    // NYTT: lokalt UI-state för tystade releaser
    @State private var mutedIds: Set<Int> = NotificationManager.mutedReleaseIds

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(NSLocalizedString("Loading upcoming releases…", comment: "Loading state for upcoming releases"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("Failed to load upcoming releases", comment: "Title for error when loading upcoming releases fails"))
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(NSLocalizedString("Try Again", comment: "Retry button")) {
                            Task { await loadReleases() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if releases.isEmpty && recentReleases.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("No upcoming releases found", comment: "Empty state title when no upcoming releases"))
                            .font(.headline)
                        Text(NSLocalizedString("We’ll show future editions from your Want to Read list here.", comment: "Empty state subtitle for upcoming releases"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        // Tips om att aktivera notiser
                        if !notificationsEnabled {
                            Button {
                                // Visa info först
                                showNotificationsInfo = true
                            } label: {
                                Label(NSLocalizedString("Enable release notifications", comment: ""), systemImage: "bell")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRequestingAuth)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(releases) { item in
                                HStack(spacing: 12) {
                                    if let data = item.coverImageData, let ui = UIImage(data: data) {
                                        Image(uiImage: ui)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 48, height: 72)
                                            .clipped()
                                            .cornerRadius(6)
                                    } else {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(UIColor.tertiarySystemFill))
                                            .frame(width: 48, height: 72)
                                            .overlay(Image(systemName: "book").foregroundColor(.secondary))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .lineLimit(2)

                                        Text(item.author)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)

                                        HStack(spacing: 6) {
                                            Image(systemName: "calendar")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(formatted(date: item.releaseDate))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            if let badge = daysBadge(for: item.releaseDate) {
                                                Text(badge.text)
                                                    .font(.caption2)
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(badge.color.opacity(0.15))
                                                    .foregroundColor(badge.color)
                                                    .cornerRadius(6)
                                            }
                                            if notificationsEnabled {
                                                Button {
                                                    Task { await toggleMute(for: item) }
                                                } label: {
                                                    let isMuted = mutedIds.contains(item.id)
                                                    Image(systemName: isMuted ? "bell.slash" : "bell.badge")
                                                        .foregroundColor(isMuted ? .secondary : .accentColor)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel(
                                                    mutedIds.contains(item.id)
                                                    ? Text(NSLocalizedString("Notifications muted for this book", comment: ""))
                                                    : Text(NSLocalizedString("Notifications enabled for this book", comment: ""))
                                                )
                                            }
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedBookForDetails = makeBookProgress(from: item)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        } footer: {
                            if notificationsEnabled {
                                Text(NSLocalizedString("You’ll get a notification at 9:00 on the release day. You can mute individual books using the bell icon.", comment: "Footer explaining notification time and per-item mute"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(NSLocalizedString("Turn on notifications to be alerted on the morning of a release day.", comment: "Footer encouraging enabling notifications"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Sektion för nyligen släppta böcker
                        if !recentReleases.isEmpty {
                            Section {
                                ForEach(recentReleases) { item in
                                    HStack(spacing: 12) {
                                        if let data = item.coverImageData, let ui = UIImage(data: data) {
                                            Image(uiImage: ui)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 48, height: 72)
                                                .clipped()
                                                .cornerRadius(6)
                                        } else {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color(UIColor.tertiarySystemFill))
                                                .frame(width: 48, height: 72)
                                                .overlay(Image(systemName: "book").foregroundColor(.secondary))
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .lineLimit(2)

                                            Text(item.author)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)

                                            HStack(spacing: 6) {
                                                Image(systemName: "calendar")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text(formatted(date: item.releaseDate))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                // Badge för redan släppt
                                                Text(NSLocalizedString("Released", comment: "Badge for already released item"))
                                                    .font(.caption2)
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(Color.gray.opacity(0.15))
                                                    .foregroundColor(.gray)
                                                    .cornerRadius(6)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedBookForDetails = makeBookProgress(from: item)
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                }
                            } header: {
                                Text(NSLocalizedString("Recently Released", comment: "Header for recently released books section"))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            } footer: {
                                Text(NSLocalizedString("These books from your Want to Read list have been released.", comment: "Footer explaining recent releases section"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("Upcoming & Recent Releases", comment: "Navigation title for upcoming and recent releases screen"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            Task { await loadReleases() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        Button {
                            Task { await notificationsButtonTapped() }
                        } label: {
                            if isRequestingAuth {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: notificationsEnabled ? "bell.slash" : "bell")
                            }
                        }
                        .accessibilityLabel(notificationsEnabled ? Text(NSLocalizedString("Disable notifications", comment: "")) : Text(NSLocalizedString("Enable notifications", comment: "")))
                    }
                }
            }
        }
        .task { await loadReleases() }
        // NYTT: presentera bokdetaljer (med beskrivning och nu även genrer/moods + recensioner + medelbetyg)
        .sheet(item: $selectedBookForDetails) { book in
            InlineReleaseBookDetailView(book: book)
        }
        // NYTT: förklaring innan vi ber om tillstånd
        .alert(
            NSLocalizedString("Enable release notifications?", comment: "Alert title asking to enable notifications"),
            isPresented: $showNotificationsInfo
        ) {
            Button(NSLocalizedString("Not now", comment: "Alert cancel"), role: .cancel) { }
            Button(NSLocalizedString("Enable", comment: "Alert confirm")) {
                Task { await enableNotificationsFlow() }
            }
        } message: {
            Text(
                NSLocalizedString(
                    "We’ll send you a notification the morning a book on your Want to Read list is released. You can turn this off anytime.",
                    comment: "Alert message explaining why notifications are requested"
                )
            )
        }
        .onAppear {
            mutedIds = NotificationManager.mutedReleaseIds
        }
    }

    private func notificationsButtonTapped() async {
        if notificationsEnabled {
            // Stäng av direkt
            await NotificationManager.clearAllReleaseNotifications()
            await MainActor.run {
                notificationsEnabled = false
                NotificationManager.isEnabled = false
            }
        } else {
            // Visa info först, sen be om tillstånd
            await MainActor.run { showNotificationsInfo = true }
        }
    }

    private func enableNotificationsFlow() async {
        await MainActor.run { isRequestingAuth = true }
        let granted = await NotificationManager.requestAuthorization()
        await MainActor.run {
            isRequestingAuth = false
            notificationsEnabled = granted
        }
        if granted {
            await NotificationManager.scheduleReleaseNotifications(for: releases)
        }
    }
    
    private func toggleMute(for item: HardcoverService.UpcomingRelease) async {
        let currentlyMuted = mutedIds.contains(item.id)
        // Uppdatera lokalt UI direkt
        await MainActor.run {
            if currentlyMuted {
                mutedIds.remove(item.id)
            } else {
                mutedIds.insert(item.id)
            }
        }
        // Spara och uppdatera pending notiser
        NotificationManager.setMuted(!currentlyMuted, for: item.id)
        if currentlyMuted {
            // Avtystad -> på: schemalägg bara denna
            await NotificationManager.scheduleReleaseNotification(for: item)
        } else {
            // På -> tystad: ta bort denna
            await NotificationManager.removeNotification(for: item.id)
        }
    }

    private func loadReleases() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        // Ladda både kommande och nyligen släppta böcker parallellt
        async let upcomingItems = HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: 30)
        async let recentItems = HardcoverService.fetchRecentReleasesFromWantToRead(limit: 10)
        
        let (upcoming, recent) = await (upcomingItems, recentItems)
        
        await MainActor.run {
            releases = upcoming
            recentReleases = recent
            isLoading = false
            if upcoming.isEmpty && recent.isEmpty {
                errorMessage = nil
            }
        }
        // Schemalägg/uppdatera notiser om aktiverat
        if notificationsEnabled {
            await NotificationManager.scheduleReleaseNotifications(for: releases)
        }
    }

    private func formatted(date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func daysBadge(for date: Date) -> (text: String, color: Color)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        guard let days = cal.dateComponents([.day], from: start, to: target).day else { return nil }
        if days < 0 {
            return (NSLocalizedString("Released", comment: "Badge for already released item"), .gray)
        } else if days == 0 {
            return (NSLocalizedString("Today", comment: "Badge for release happening today"), .green)
        } else if days == 1 {
            return (NSLocalizedString("Tomorrow", comment: "Badge for release happening tomorrow"), .green)
        } else {
            let text = String.localizedStringWithFormat(
                NSLocalizedString("In %d days", comment: "Badge for release happening in N days"),
                days
            )
            return (text, .blue)
        }
    }
    
    // Skapa ett minimalt BookProgress-objekt från en release
    private func makeBookProgress(from release: HardcoverService.UpcomingRelease) -> BookProgress {
        return BookProgress(
            id: "release-\(release.id)",
            title: release.title,
            author: release.author,
            coverImageData: release.coverImageData,
            progress: 0.0,
            totalPages: 0,
            currentPage: 0,
            bookId: release.bookId,
            userBookId: nil,
            editionId: release.id,
            originalTitle: release.title,
            editionAverageRating: nil,
            userRating: nil,
            bookDescription: nil
        )
    }
}

// Minimal detaljvy (utan framsteg), med beskrivning + dynamiska genres & moods + recensioner + medelbetyg
private struct InlineReleaseBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let book: BookProgress
    @State private var descriptionText: String?
    @State private var isLoadingDescription = false
    
    // NYTT: Genres & Moods state
    @State private var genres: [String] = []
    @State private var isLoadingGenres = false
    @State private var moods: [String] = []
    @State private var isLoadingMoods = false
    
    // NYTT: Average rating (fallback om book.editionAverageRating saknas)
    @State private var averageRating: Double?
    
    // NYTT: Reviews state
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @State private var reviews: [HardcoverService.PublicReview] = []
    @State private var reviewsPage = 0
    private let reviewsPageSize = 10
    @State private var canLoadMoreReviews = true
    
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
                            
                            // Average rating row (same placement/look as other detail views)
                            if let avg = (book.editionAverageRating ?? averageRating) {
                                HStack(spacing: 8) {
                                    InlineReadOnlyStars(rating: avg)
                                    Text(String(format: NSLocalizedString("Average %.1f", comment: ""), avg))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // GENRES chips under författarnamn – samma mönster som i vill läsa-detaljvyn
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
                            
                            // Separator om båda finns
                            if !genres.isEmpty && !moods.isEmpty {
                                Divider()
                                    .padding(.vertical, 2)
                            }
                            
                            // MOODS chips
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

                    
                    // Beskrivning
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
                    
                    // Reviews section (NYTT)
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
                    }
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("Book Details", comment: "Title for book details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "Close button")) { dismiss() }
                }
            }
        }
        .task {
            // Parallellt: beskrivning + taxonomier (genrer/moods) + ev. medelbetyg (bok)
            async let loadDesc: Void = {
                if descriptionText == nil, (book.bookDescription == nil || book.bookDescription?.isEmpty == true),
                   let id = book.bookId {
                    await MainActor.run { isLoadingDescription = true }
                    let fetched = await fetchBookDescription(bookId: id)
                    await MainActor.run {
                        descriptionText = fetched
                        isLoadingDescription = false
                    }
                }
            }()
            async let loadTax: Void = { await reloadTaxonomies() }()
            async let loadAvg: Void = {
                if book.editionAverageRating == nil, let id = book.bookId {
                    let avg = await fetchBookAverageRating(bookId: id)
                    await MainActor.run { averageRating = avg }
                }
            }()
            _ = await (loadDesc, loadTax, loadAvg)
        }
    }
    
    // Ladda genrer+moods parallellt (taggings först, sedan cached_tags) – identiskt mönster som i vill läsa-detaljvyn
    private func reloadTaxonomies() async {
        await MainActor.run {
            if genres.isEmpty { isLoadingGenres = true }
            if moods.isEmpty { isLoadingMoods = true }
        }
        async let g = fetchGenresPreferred(bookId: book.bookId, editionId: book.editionId, userBookId: book.userBookId)
        async let m = fetchMoodsPreferred(bookId: book.bookId, editionId: book.editionId, userBookId: book.userBookId)
        let (gList, mList) = await (g, m)
        await MainActor.run {
            self.genres = gList
            self.moods = mList
            self.isLoadingGenres = false
            self.isLoadingMoods = false
        }
    }
    
    // Enkel beskrivningshämtning via GraphQL
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
               let first = books.first,
               let desc = first["description"] as? String {
                return desc
            }
        } catch {
            return nil
        }
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
    
    // Ladda genrer+moods – samma mönster som i andra vyer
    private func fetchGenresPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        // 1) via taggings (book)
        if let bid = bookId {
            if let arr = await queryBookGenresViaTaggings(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // 2) via taggings (user_book -> book)
        if let ubid = userBookId {
            if let arr = await queryUserBookGenresViaTaggings(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // 3) via cached_tags (book)
        if let bid = bookId {
            if let arr = await queryBookCachedGenres(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // 4) via cached_tags (user_book -> book)
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
            taggings(limit: 200) {
              tag { tag tag_category { slug } }
            }
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
        } catch {
            return nil
        }
        return nil
    }
    
    private func queryUserBookGenresViaTaggings(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book {
              id
              taggings(limit: 200) {
                tag { tag tag_category { slug } }
              }
            }
            edition {
              id
              book {
                id
                taggings(limit: 200) {
                  tag { tag tag_category { slug } }
                }
              }
            }
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
                   let arr = extractGenresFromTaggings(book["taggings"]),
                   !arr.isEmpty {
                    return arr
                }
            }
        } catch {
            return nil
        }
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
        // Same query shape as genres; we filter in extractor by category slug == "mood"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            taggings(limit: 200) {
              tag { tag tag_category { slug } }
            }
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
                return extractMoodsFromTaggings(first["taggings"])
            }
        } catch {
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
            book {
              id
              taggings(limit: 200) {
                tag { tag tag_category { slug } }
              }
            }
          }
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
                return extractMoodsFromTaggings(book["taggings"])
            }
        } catch {
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
            book {
              id
              taggings(limit: 200) {
                tag { tag tag_category { slug } }
              }
            }
            edition {
              id
              book {
                id
                taggings(limit: 200) {
                  tag { tag tag_category { slug } }
                }
              }
            }
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
                   let arr = extractMoodsFromTaggings(book["taggings"]),
                   !arr.isEmpty {
                    return arr
                }
                if let ed = first["edition"] as? [String: Any],
                   let b = ed["book"] as? [String: Any],
                   let arr = extractMoodsFromTaggings(b["taggings"]),
                   !arr.isEmpty {
                    return arr
                }
            }
        } catch {
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
    
    // MARK: cached_tags-vägen (Genres)
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
        } catch {
            return nil
        }
        return nil
    }
    
    private func queryEditionBookCachedGenres(url: URL, editionId: Int) async -> [String]? {
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
                return extractGenres(fromCachedTags: book["cached_tags"])
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func queryUserBookCachedGenres(url: URL, userBookId: Int) async -> [String]? {
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
                   let arr = extractGenres(fromCachedTags: book["cached_tags"]),
                   !arr.isEmpty {
                    return arr
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // Robust parser för cached_tags -> [genre-namn]
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
        } catch {
            return nil
        }
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
        } catch {
            return nil
        }
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
        } catch {
            return nil
        }
        return nil
    }
    
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
    
    // Wrap-layout för chips – samma som i vill läsa-detaljvyn
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
    
    // Inline review row with like/unlike (speglar övriga vyer)
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
            
            let result = await setLike(likeableId: review.id, like: newLikeState, likeableType: "UserBook")
            
            await MainActor.run {
                if let result {
                    likesCount = max(0, result.likesCount)
                    userHasLiked = result.didLike
#if os(iOS) && !targetEnvironment(macCatalyst)
                    if userHasLiked {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
#endif
                } else {
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
}

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

#Preview {
    UpcomingReleasesView()
}
