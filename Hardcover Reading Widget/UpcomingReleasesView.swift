import SwiftUI

struct UpcomingReleasesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var releases: [HardcoverService.UpcomingRelease] = []
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
                } else if releases.isEmpty {
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
                                Text(NSLocalizedString("You’ll get a notification at 8:00 on the release day. You can mute individual books using the bell icon.", comment: "Footer explaining notification time and per-item mute"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(NSLocalizedString("Turn on notifications to be alerted on the morning of a release day.", comment: "Footer encouraging enabling notifications"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("Upcoming Releases", comment: "Navigation title for upcoming releases screen"))
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Done", comment: "Done button title")) { dismiss() }
                }
            }
        }
        .task { await loadReleases() }
        // NYTT: presentera bokdetaljer (med beskrivning om tillgänglig)
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
        let items = await HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: 30)
        await MainActor.run {
            releases = items
            isLoading = false
            if items.isEmpty {
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

// Minimal detaljvy (utan framsteg), med beskrivning om tillgänglig
private struct InlineReleaseBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let book: BookProgress
    @State private var descriptionText: String?
    @State private var isLoadingDescription = false
    
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Medelbetyg (om vi får det i framtiden)
                    if let avg = book.editionAverageRating {
                        HStack(spacing: 8) {
                            InlineReadOnlyStars(rating: avg)
                            Text(String(format: NSLocalizedString("Average %.1f", comment: ""), avg))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
            // Hämta beskrivning om vi har ett bookId men ingen beskrivning ännu
            if descriptionText == nil, (book.bookDescription == nil || book.bookDescription?.isEmpty == true),
               let id = book.bookId {
                isLoadingDescription = true
                descriptionText = await fetchBookDescription(bookId: id)
                isLoadingDescription = false
            }
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
    
    // Enkel sanering av HTML-taggar
    private func normalizedDescription(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let withoutTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return withoutTags.trimmingCharacters(in: .whitespacesAndNewlines)
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
