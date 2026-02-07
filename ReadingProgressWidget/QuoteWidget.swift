import WidgetKit
import SwiftUI
import AppIntents

struct QuoteWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry {
        QuoteEntry(
            date: Date(),
            quote: "Reading is essential for those who seek to rise above the ordinary.",
            bookTitle: "The Book Thief",
            authorName: "Markus Zusak",
            quoteId: nil,
            bookId: nil,
            configuration: QuoteUpdateIntervalIntent()
        )
    }
    
    func snapshot(for configuration: QuoteUpdateIntervalIntent, in context: Context) async -> QuoteEntry {
        QuoteEntry(
            date: Date(),
            quote: "Reading is essential for those who seek to rise above the ordinary.",
            bookTitle: "The Book Thief",
            authorName: "Markus Zusak",
            quoteId: nil,
            bookId: nil,
            configuration: configuration
        )
    }
    
    func timeline(for configuration: QuoteUpdateIntervalIntent, in context: Context) async -> Timeline<QuoteEntry> {
        let quotes = await HardcoverService.fetchReadingJournalQuotes()
        let updateHours = (configuration.updateInterval ?? .fourHours).hours

        guard !quotes.isEmpty else {
            let entry = QuoteEntry(
                date: Date(),
                quote: "No quotes found. Add quotes to your Reading Journal on Hardcover!",
                bookTitle: "",
                authorName: "",
                quoteId: nil,
                bookId: nil,
                configuration: configuration
            )
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: updateHours, to: Date())!
            return Timeline(entries: [entry], policy: .after(nextUpdate))
        }

        // Pick one random quote to show now. Each widget instance calls
        // timeline() independently, so they each get their own random pick.
        // The refresh button triggers reloadTimelines which calls this again
        // with a new random selection.
        let picked = quotes.randomElement()!
        let authorNames = picked.book.contributions
            .compactMap { $0.author?.name }
            .joined(separator: ", ")

        let now = Date()
        let entry = QuoteEntry(
            date: now,
            quote: picked.entry,
            bookTitle: picked.book.title,
            authorName: authorNames.isEmpty ? "Unknown Author" : authorNames,
            quoteId: picked.id,
            bookId: picked.bookId,
            configuration: configuration
        )

        // Schedule next automatic update after the configured interval
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: updateHours, to: now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

struct QuoteEntry: TimelineEntry {
    let date: Date
    let quote: String
    let bookTitle: String
    let authorName: String
    let quoteId: Int?
    let bookId: Int?
    let configuration: QuoteUpdateIntervalIntent
    
    /// Deep link URL for opening this specific quote in the app
    var deepLinkURL: URL? {
        guard let quoteId = quoteId, let bookId = bookId else { return nil }
        return URL(string: "softcover://quote?quoteId=\(quoteId)&bookId=\(bookId)")
    }
}

struct QuoteWidgetView: View {
    var entry: QuoteEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        if family == .systemSmall {
            // Small widget - original layout
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Button(intent: QuoteRefreshIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)
                
                Text(entry.quote)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(8)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                if !entry.bookTitle.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.bookTitle)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        
                        Text(entry.authorName)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(12)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.1, blue: 0.15), Color(red: 0.15, green: 0.1, blue: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            // Medium widget - quote icon at bottom
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(intent: QuoteRefreshIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)
                
                Text(entry.quote)
                    .font(.callout)
                    .foregroundColor(.white)
                    .lineLimit(6)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment:
 .topLeading)
                
                Spacer(minLength: 6)
                
                if !entry.bookTitle.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.8))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.bookTitle)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                            
                            Text(entry.authorName)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.1, blue: 0.15), Color(red: 0.15, green: 0.1, blue: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct QuoteWidget: Widget {
    let kind: String = "QuoteWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuoteUpdateIntervalIntent.self, provider: QuoteWidgetProvider()) { entry in
            QuoteWidgetView(entry: entry)
                .widgetURL(entry.deepLinkURL)
        }
        .configurationDisplayName("Reading Quote")
        .description("Display a random quote from your Reading Journal")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    QuoteWidget()
} timeline: {
    QuoteEntry(
        date: Date(),
        quote: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
        bookTitle: "Pride and Prejudice",
        authorName: "Jane Austen",
        quoteId: 1,
        bookId: 100,
        configuration: QuoteUpdateIntervalIntent()
    )
    QuoteEntry(
        date: Date(),
        quote: "The only way out of the labyrinth of suffering is to forgive.",
        bookTitle: "Looking for Alaska",
        authorName: "John Green",
        quoteId: 2,
        bookId: 200,
        configuration: QuoteUpdateIntervalIntent()
    )
}

#Preview(as: .systemMedium) {
    QuoteWidget()
} timeline: {
    QuoteEntry(
        date: Date(),
        quote: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
        bookTitle: "Pride and Prejudice",
        authorName: "Jane Austen",
        quoteId: 1,
        bookId: 100,
        configuration: QuoteUpdateIntervalIntent()
    )
}
