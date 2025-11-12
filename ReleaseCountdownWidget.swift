import SwiftUI
import WidgetKit
import AppIntents

struct ReleaseCountdownEntry: TimelineEntry {
    let date: Date
    let releases: [HardcoverService.UpcomingRelease]
}

struct ReleaseCountdownProvider: AppIntentTimelineProvider {
    typealias Intent = ReleaseSelectionIntent
    
    func placeholder(in context: Context) -> ReleaseCountdownEntry {
        let sample = HardcoverService.UpcomingRelease(
            id: 999,
            bookId: 123,
            title: "The Winds of Winter",
            author: "George R.R. Martin",
            releaseDate: Calendar.current.date(byAdding: .day, value: 42, to: Date())!,
            coverImageData: nil
        )
        return ReleaseCountdownEntry(date: Date(), releases: [sample])
    }
    
    func snapshot(for configuration: ReleaseSelectionIntent, in context: Context) async -> ReleaseCountdownEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        let list = await loadReleasesRespectedBySelection(configuration: configuration, cap: 4)
        return ReleaseCountdownEntry(date: Date(), releases: list)
    }
    
    func timeline(for configuration: ReleaseSelectionIntent, in context: Context) async -> Timeline<ReleaseCountdownEntry> {
        let list = await loadReleasesRespectedBySelection(configuration: configuration, cap: 4)
        let entry = ReleaseCountdownEntry(date: Date(), releases: list)
        
        // Uppdatera en gång per dygn: strax efter lokal midnatt (00:05).
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        let startOfTomorrow = cal.startOfDay(for: tomorrow)
        let nextRefresh = cal.date(byAdding: .minute, value: 5, to: startOfTomorrow)!
        
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
    
    // MARK: - Helpers
    private func loadReleasesRespectedBySelection(configuration: ReleaseSelectionIntent, cap: Int) async -> [HardcoverService.UpcomingRelease] {
        // Hämta tillräckligt många för val + alla widgetstorlekar
        var list = await HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: max(30, cap))
        
        // Filtrera på användarens val om något är valt och behåll deras ordning
        let selected = configuration.releases
        if !selected.isEmpty {
            var order: [Int: Int] = [:]
            for (i, e) in selected.enumerated() {
                if let id = Int(e.id) { order[id] = i }
            }
            let selectedIds = Set(order.keys)
            list = list
                .filter { selectedIds.contains($0.id) }
                .sorted { (a, b) -> Bool in
                    (order[a.id] ?? Int.max) < (order[b.id] ?? Int.max)
                }
        }
        
        return Array(list.prefix(cap))
    }
}

struct ReleaseCountdownWidgetEntryView: View {
    var entry: ReleaseCountdownProvider.Entry
    @Environment(\.widgetFamily) private var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallReleaseView(item: entry.releases.first)
                .containerBackground(.fill.tertiary, for: .widget)
        case .systemMedium:
            MediumReleaseListView(items: Array(entry.releases.prefix(2)))
                .containerBackground(.fill.tertiary, for: .widget)
        case .systemLarge:
            LargeReleaseListView(items: Array(entry.releases.prefix(4)))
                .containerBackground(.fill.tertiary, for: .widget)
        default:
            MediumReleaseListView(items: Array(entry.releases.prefix(2)))
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Shared helpers
private func daysUntil(_ date: Date) -> Int {
    let cal = Calendar.current
    let startToday = cal.startOfDay(for: Date())
    let startTarget = cal.startOfDay(for: date)
    return cal.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
}

private func formatDate(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df.string(from: date)
}

// MARK: - Small: Full‑bleed “poster” style
private struct SmallReleaseView: View {
    let item: HardcoverService.UpcomingRelease?
    
    var body: some View {
        ZStack {
            // Background image (full‑bleed)
            if let data = item?.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                // Fallback background
                LinearGradient(
                    colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Image(systemName: "book.closed")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Bottom gradient overlay for legibility
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)]),
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            // Bottom-left label(s)
            VStack(alignment: .leading, spacing: 2) {
                if let item {
                    let d = daysUntil(item.releaseDate)
                    Text(d <= 0 ? NSLocalizedString("Today!", comment: "") : String(format: NSLocalizedString("%d days", comment: ""), d))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    
                    Text(formatDate(item.releaseDate))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                } else {
                    Text(NSLocalizedString("No release", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        // Viktigt i widgets: låt systemet sköta hörnradien via containerBackground
        .contentShape(Rectangle())
    }
}

// MARK: - Medium & Large list layouts (oförändrade)
private struct MediumReleaseListView: View {
    let items: [HardcoverService.UpcomingRelease]
    
    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("No upcoming releases")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.prefix(2), id: \.id) { item in
                    HStack(spacing: 10) {
                        if let data = item.coverImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .widgetAccentedRenderingMode(.fullColor)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 56)
                                .clipped()
                                .cornerRadius(4)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.25))
                                .frame(width: 40, height: 56)
                                .overlay(Image(systemName: "book.closed").foregroundColor(.gray))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(item.author)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            HStack {
                                let d = daysUntil(item.releaseDate)
                                Text(d <= 0 ? NSLocalizedString("Today", comment: "") : String(format: NSLocalizedString("%d days", comment: ""), d))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatDate(item.releaseDate))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }
}

private struct LargeReleaseListView: View {
    let items: [HardcoverService.UpcomingRelease]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("Upcoming Releases", comment: "Widget title"))
                    .font(.headline)
                Spacer()
            }
            if items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No upcoming releases")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items.prefix(4), id: \.id) { item in
                        HStack(spacing: 10) {
                            if let data = item.coverImageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .widgetAccentedRenderingMode(.fullColor)
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 62)
                                    .clipped()
                                    .cornerRadius(5)
                            } else {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.gray.opacity(0.25))
                                    .frame(width: 44, height: 62)
                                    .overlay(Image(systemName: "book.closed").foregroundColor(.gray))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                Text(item.author)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                HStack {
                                    let d = daysUntil(item.releaseDate)
                                    Text(d <= 0 ? NSLocalizedString("Releases today", comment: "") : String(format: NSLocalizedString("%d days left", comment: ""), d))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatDate(item.releaseDate))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }
}

struct ReleaseCountdownWidget: Widget {
    let kind: String = "ReleaseCountdownWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ReleaseSelectionIntent.self,
            provider: ReleaseCountdownProvider()
        ) { entry in
            ReleaseCountdownWidgetEntryView(entry: entry)
                // Make the whole widget open Upcoming Releases in the app
                .widgetURL(URL(string: "softcover://upcoming")!)
        }
        .configurationDisplayName("Upcoming Releases")
        .description("Shows countdowns for upcoming book releases from your Want to Read list.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    ReleaseCountdownWidget()
} timeline: {
    let sample = HardcoverService.UpcomingRelease(
        id: 1,
        bookId: 1,
        title: "Sample Book",
        author: "Sample Author",
        releaseDate: Calendar.current.date(byAdding: .day, value: 0, to: .now)!,
        coverImageData: nil
    )
    ReleaseCountdownEntry(date: .now, releases: [sample])
}
