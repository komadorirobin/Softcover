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
            configuration: QuoteUpdateIntervalIntent()
        )
    }
    
    func snapshot(for configuration: QuoteUpdateIntervalIntent, in context: Context) async -> QuoteEntry {
        QuoteEntry(
            date: Date(),
            quote: "Reading is essential for those who seek to rise above the ordinary.",
            bookTitle: "The Book Thief",
            authorName: "Markus Zusak",
            configuration: configuration
        )
    }
    
    func timeline(for configuration: QuoteUpdateIntervalIntent, in context: Context) async -> Timeline<QuoteEntry> {
        let quotes = await HardcoverService.fetchReadingJournalQuotes()
        
        let entry: QuoteEntry
        if let randomQuote = quotes.randomElement() {
            let authorNames = randomQuote.book.contributions
                .compactMap { $0.author?.name }
                .joined(separator: ", ")
            
            entry = QuoteEntry(
                date: Date(),
                quote: randomQuote.entry,
                bookTitle: randomQuote.book.title,
                authorName: authorNames.isEmpty ? "Unknown Author" : authorNames,
                configuration: configuration
            )
        } else {
            entry = QuoteEntry(
                date: Date(),
                quote: "No quotes found. Add quotes to your Reading Journal on Hardcover!",
                bookTitle: "",
                authorName: "",
                configuration: configuration
            )
        }
        
        // Use the configured update interval
        let updateHours = (configuration.updateInterval ?? .fourHours).hours
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: updateHours, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        return timeline
    }
}

struct QuoteEntry: TimelineEntry {
    let date: Date
    let quote: String
    let bookTitle: String
    let authorName: String
    let configuration: QuoteUpdateIntervalIntent
}

struct QuoteWidgetView: View {
    var entry: QuoteEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with quote icon and refresh button
            HStack {
                Image(systemName: "quote.opening")
                    .font(.system(size: family == .systemSmall ? 16 : 20))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Button(intent: QuoteRefreshIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: family == .systemSmall ? 12 : 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, family == .systemSmall ? 6 : 8)
            
            // Quote text
            Text(entry.quote)
                .font(family == .systemSmall ? .caption : .subheadline)
                .foregroundColor(.white)
                .lineLimit(family == .systemSmall ? 4 : 5)
                .lineSpacing(family == .systemSmall ? 1 : 2)
            
            Spacer(minLength: 0)
            
            // Book info - fixed at bottom
            if !entry.bookTitle.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.bookTitle)
                        .font(family == .systemSmall ? .caption2 : .caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    
                    Text(entry.authorName)
                        .font(family == .systemSmall ? .caption2 : .caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.top, family == .systemSmall ? 6 : 8)
            }
        }
        .padding(family == .systemSmall ? 12 : 16)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.1, blue: 0.15), Color(red: 0.15, green: 0.1, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct QuoteWidget: Widget {
    let kind: String = "QuoteWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuoteUpdateIntervalIntent.self, provider: QuoteWidgetProvider()) { entry in
            QuoteWidgetView(entry: entry)
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
        configuration: QuoteUpdateIntervalIntent()
    )
    QuoteEntry(
        date: Date(),
        quote: "The only way out of the labyrinth of suffering is to forgive.",
        bookTitle: "Looking for Alaska",
        authorName: "John Green",
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
        configuration: QuoteUpdateIntervalIntent()
    )
}
