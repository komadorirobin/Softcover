import WidgetKit
import SwiftUI
import AppIntents

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        // Lokal placeholder-bok för förhandsvisning
        let placeholderBook = BookProgress(
            id: "1",
            title: "The Lord of the Rings",
            author: "J.R.R. Tolkien",
            coverImageData: nil,
            progress: 0.75,
            totalPages: 1178,
            currentPage: 883,
            bookId: 1,
            userBookId: 1,
            editionId: 1,
            originalTitle: "The Lord of the Rings"
        )
        return SimpleEntry(date: Date(), books: [placeholderBook], configuration: BookSelectionIntent())
    }

    func snapshot(for configuration: BookSelectionIntent, in context: Context) async -> SimpleEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        // Widgets: använd mindre bilder för att spara minne/bandbredd
        let loaded = await WidgetReaders.reading(selectedIDs: configuration.displayMode == .manualSelection ? (configuration.books ?? []).map(\.id) : [])
        let filteredBooks = filterBooks(allBooks: loaded.value, configuration: configuration)
        return SimpleEntry(date: loaded.date, books: filteredBooks, configuration: configuration, failed: loaded.failed)
    }
    
    func timeline(for configuration: BookSelectionIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let loaded = await WidgetReaders.reading(selectedIDs: configuration.displayMode == .manualSelection ? (configuration.books ?? []).map(\.id) : [])
        let filteredBooks = filterBooks(allBooks: loaded.value, configuration: configuration)
        let entry = SimpleEntry(date: loaded.date, books: filteredBooks, configuration: configuration, failed: loaded.failed)
        // A signed-out or genuinely empty library does not need a five-minute poll.
        let interval: TimeInterval = HardcoverConfig.apiKey.isEmpty ? 21600 : (loaded.failed ? 900 : 1800)
        let nextUpdate = Date().addingTimeInterval(interval)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    func recommendations() -> [AppIntentRecommendation<BookSelectionIntent>] {
        return []
    }
    
    private func filterBooks(allBooks: [BookProgress], configuration: BookSelectionIntent) -> [BookProgress] {
        // If Recently Updated mode, sort by most recently updated
        if configuration.displayMode == .recentlyUpdated {
            // Books are already sorted by update time from the API (order_by: {id: desc})
            return allBooks
        }
        
        // Manual Selection mode
        guard let selectedBooks = configuration.books, !selectedBooks.isEmpty else {
            return allBooks
        }
        var filtered: [BookProgress] = []
        for selected in selectedBooks {
            if let match = allBooks.first(where: { $0.id == selected.id }) {
                filtered.append(match)
            }
        }
        if filtered.isEmpty && !allBooks.isEmpty {
            return allBooks
        }
        return filtered
    }

}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let books: [BookProgress]
    let configuration: BookSelectionIntent
    var failed = false
}

struct ReadingProgressWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    var body: some View {
        let firstBook = entry.books.first
        if entry.failed && entry.books.isEmpty {
            NoBooksView(unavailable: true)
                .containerBackground(.fill.tertiary, for: .widget)
        } else {
            switch family {
            case .systemSmall:
                SmallWidgetView(book: firstBook)
                    .containerBackground(.fill.tertiary, for: .widget)
            case .systemMedium:
                MediumWidgetView(books: Array(entry.books.prefix(2)))
                    .containerBackground(.fill.tertiary, for: .widget)
            case .systemLarge:
                LargeWidgetView(books: Array(entry.books.prefix(4)), lastUpdated: entry.date)
                    .containerBackground(.fill.tertiary, for: .widget)
            default:
                MediumWidgetView(books: Array(entry.books.prefix(2)))
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
    }
}

struct ReadingProgressWidget: Widget {
    let kind: String = "ReadingProgressWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BookSelectionIntent.self,
            provider: Provider()
        ) { entry in
            ReadingProgressWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Currently Reading")
        .description("Displays your currently reading books from Hardcover.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Bundle that exposes all widgets
@main
struct ReadingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadingProgressWidget()
        ReadingGoalWidget()
        ReleaseCountdownWidget()
        QuoteWidget()
    }
}

#Preview(as: .systemSmall) {
    ReadingProgressWidget()
} timeline: {
    let previewBook = BookProgress(
        id: "1",
        title: "A Game of Thrones",
        author: "George R.R. Martin",
        coverImageData: nil,
        progress: 0.5,
        totalPages: 694,
        currentPage: 347,
        bookId: 1,
        userBookId: 1,
        editionId: 1,
        originalTitle: "A Game of Thrones"
    )
    SimpleEntry(date: Date(), books: [previewBook], configuration: BookSelectionIntent())
}
