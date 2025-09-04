import SwiftUI
import WidgetKit

struct ReleaseCountdownEntry: TimelineEntry {
    let date: Date
    let releases: [HardcoverService.UpcomingRelease]
}

struct ReleaseCountdownProvider: TimelineProvider {
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
    
    func getSnapshot(in context: Context, completion: @escaping (ReleaseCountdownEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            // Hämta bara det som kan visas: 6 räcker för både medium (3) och large (6)
            let list = await HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: 6)
            completion(ReleaseCountdownEntry(date: Date(), releases: list))
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReleaseCountdownEntry>) -> Void) {
        Task {
            // Hämta bara det som kan visas: 6 räcker för både medium (3) och large (6)
            let list = await HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: 6)
            let entry = ReleaseCountdownEntry(date: Date(), releases: list)
            
            // Smart refresh: vid nästa release-datum (strax efter lokal midnatt) eller fallback
            let nextRefresh: Date = {
                if let first = list.first {
                    // Schemalägg strax efter att release-dagen börjar (lokal midnatt + 5 min)
                    let cal = Calendar.current
                    let startOfRelease = cal.startOfDay(for: first.releaseDate)
                    let candidate = cal.date(byAdding: .minute, value: 5, to: startOfRelease) ?? Date().addingTimeInterval(3600)
                    if candidate > Date() {
                        return candidate
                    }
                }
                // Annars, uppdatera periodiskt
                return Calendar.current.date(byAdding: .hour, value: 6, to: Date())!
            }()
            
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
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
            MediumReleaseListView(items: Array(entry.releases.prefix(3)))
                .containerBackground(.fill.tertiary, for: .widget)
        case .systemLarge:
            LargeReleaseListView(items: Array(entry.releases.prefix(6)))
                .containerBackground(.fill.tertiary, for: .widget)
        default:
            MediumReleaseListView(items: Array(entry.releases.prefix(3)))
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Views
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

private struct SmallReleaseView: View {
    let item: HardcoverService.UpcomingRelease?
    
    var body: some View {
        if let item = item {
            VStack(spacing: 6) {
                if let data = item.coverImageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 94)
                        .clipped()
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.2), radius: 6, x: 2, y: 4)
                        .padding(.top, 6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 70, height: 94)
                        .overlay(Image(systemName: "book.closed").font(.title3).foregroundColor(.gray.opacity(0.5)))
                        .padding(.top, 6)
                }
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                let d = daysUntil(item.releaseDate)
                Text(d <= 0 ? NSLocalizedString("Releases today", comment: "") : String(format: NSLocalizedString("%d days left", comment: ""), d))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                Text(formatDate(item.releaseDate))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 6)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("No upcoming releases")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

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
                ForEach(items.prefix(3), id: \.id) { item in
                    HStack(spacing: 10) {
                        if let data = item.coverImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
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
                ForEach(items.prefix(6), id: \.id) { item in
                    HStack(spacing: 10) {
                        if let data = item.coverImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
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
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }
}

struct ReleaseCountdownWidget: Widget {
    let kind: String = "ReleaseCountdownWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReleaseCountdownProvider()) { entry in
            ReleaseCountdownWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Upcoming Releases")
        .description("Shows countdowns for upcoming book releases from your Want to Read list.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    ReleaseCountdownWidget()
} timeline: {
    let sample = HardcoverService.UpcomingRelease(
        id: 1,
        bookId: 1,
        title: "Sample Book",
        author: "Sample Author",
        releaseDate: Calendar.current.date(byAdding: .day, value: 5, to: .now)!,
        coverImageData: nil
    )
    ReleaseCountdownEntry(date: .now, releases: [sample])
}
