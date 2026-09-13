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
        if context.isPreview { return placeholder(in: context) }
        let loaded = await WidgetReaders.quotes()
        return makeEntry(quotes: loaded.value, configuration: configuration, failed: loaded.failed)
    }
    
    func timeline(for configuration: QuoteUpdateIntervalIntent, in context: Context) async -> Timeline<QuoteEntry> {
        let loaded = await WidgetReaders.quotes()
        let updateHours = (configuration.updateInterval ?? .fourHours).hours
        let entry = makeEntry(quotes: loaded.value, configuration: configuration, failed: loaded.failed)
        let interval = loaded.failed ? 900 : TimeInterval(updateHours * 3600)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(interval)))
    }

    private func makeEntry(quotes: [HardcoverService.ReadingJournalQuote], configuration: QuoteUpdateIntervalIntent, failed: Bool) -> QuoteEntry {
        guard let picked = quotes.randomElement() else {
            let message = HardcoverConfig.apiKey.isEmpty ? "Sign in to Hardcover" : (failed ? "Could not load quotes" : "No quotes found. Add quotes to your Reading Journal on Hardcover!")
            return QuoteEntry(date: Date(), quote: NSLocalizedString(message, comment: "Quote widget empty state"), bookTitle: "", authorName: "", quoteId: nil, bookId: nil, configuration: configuration)
        }
        let authorNames = picked.book.contributions
            .compactMap { $0.author?.name }
            .joined(separator: ", ")

        return QuoteEntry(
            date: Date(),
            quote: picked.entry,
            bookTitle: picked.book.title,
            authorName: authorNames.isEmpty ? NSLocalizedString("Unknown Author", comment: "") : authorNames,
            quoteId: picked.id,
            bookId: picked.bookId,
            configuration: configuration
        )

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
        var components = URLComponents()
        components.scheme = "softcover"
        components.host = "quote"
        components.queryItems = [
            URLQueryItem(name: "quoteId", value: String(quoteId)),
            URLQueryItem(name: "bookId", value: String(bookId)),
            URLQueryItem(name: "bookTitle", value: bookTitle)
        ]
        return components.url
    }
}

struct QuoteWidgetView: View {
    var entry: QuoteEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.showsWidgetContainerBackground) var showsBackground

    // Older widget configurations don't contain appearance parameters.
    private var theme: QuoteColorTheme { entry.configuration.colorTheme ?? .classic }
    private var fontDesign: Font.Design { (entry.configuration.font ?? .system).design }
    private var foregroundColor: Color {
        renderingMode == .fullColor && showsBackground ? theme.textColor : .primary
    }

    var body: some View {
        content
            .foregroundStyle(foregroundColor)
            .containerBackground(for: .widget) {
                if (entry.configuration.background ?? .gradient) == .solid {
                    theme.backgroundColor
                } else {
                    LinearGradient(
                        colors: [theme.backgroundColor, theme.gradientEndColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    quoteIcon(size: 18)
                    Spacer()
                    refreshButton(size: 13)
                }
                .padding(.bottom, 6)

                Text(entry.quote)
                    .font(.system(.caption, design: fontDesign))
                    .lineLimit(8)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if !entry.bookTitle.isEmpty {
                    attribution(style: .caption2)
                        .padding(.top, 6)
                }
            }
            .padding(12)
        } else if family == .systemLarge {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    quoteIcon(size: 28)
                    Spacer()
                    refreshButton(size: 17)
                }

                Text(entry.quote)
                    .font(.system(.title3, design: fontDesign))
                    .lineLimit(14)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if !entry.bookTitle.isEmpty {
                    attribution(style: .subheadline, lineLimit: 2)
                }
            }
            .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    refreshButton(size: 15)
                }
                .padding(.bottom, 2)

                Text(entry.quote)
                    .font(.system(.callout, design: fontDesign))
                    .lineLimit(6)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Spacer(minLength: 6)

                if !entry.bookTitle.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        quoteIcon(size: 22)
                        attribution(style: .caption)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func quoteIcon(size: CGFloat) -> some View {
        Image(systemName: "quote.opening")
            .font(.system(size: size))
            .foregroundStyle(foregroundColor.opacity(0.8))
            .accessibilityHidden(true)
    }

    private func refreshButton(size: CGFloat) -> some View {
        Button(intent: QuoteRefreshIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: size))
                .foregroundStyle(foregroundColor.opacity(0.7))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh Quote")
    }

    private func attribution(style: Font.TextStyle, lineLimit: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.bookTitle)
                .font(.system(style, design: fontDesign, weight: .semibold))
                .foregroundStyle(foregroundColor.opacity(0.9))
                .lineLimit(lineLimit)

            Text(entry.authorName)
                .font(.system(style, design: fontDesign))
                .foregroundStyle(foregroundColor.opacity(0.7))
                .lineLimit(lineLimit)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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

#Preview(as: .systemLarge) {
    QuoteWidget()
} timeline: {
    QuoteEntry(
        date: Date(),
        quote: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
        bookTitle: "Pride and Prejudice",
        authorName: "Jane Austen",
        quoteId: 1,
        bookId: 100,
        configuration: QuoteUpdateIntervalIntent(colorTheme: .paper, font: .serif, background: .solid)
    )
    QuoteEntry(
        date: Date(),
        quote: "The only way out of the labyrinth of suffering is to forgive.",
        bookTitle: "Looking for Alaska",
        authorName: "John Green",
        quoteId: 2,
        bookId: 200,
        configuration: QuoteUpdateIntervalIntent(colorTheme: .forest, font: .rounded)
    )
}
