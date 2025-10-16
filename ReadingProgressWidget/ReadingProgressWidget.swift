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
        logDiagnostics(context: "snapshot")
        if context.isPreview {
            return placeholder(in: context)
        }
        // Widgets: använd mindre bilder för att spara minne/bandbredd
        let allBooks = await HardcoverService.fetchCurrentlyReading()
        let filteredBooks = filterBooks(allBooks: allBooks, configuration: configuration)
        if filteredBooks.isEmpty && context.isPreview {
            return placeholder(in: context)
        }
        return SimpleEntry(date: Date(), books: filteredBooks, configuration: configuration)
    }
    
    func timeline(for configuration: BookSelectionIntent, in context: Context) async -> Timeline<SimpleEntry> {
        logDiagnostics(context: "timeline")
        // Widgets: använd mindre bilder för att spara minne/bandbredd
        let allBooks = await HardcoverService.fetchCurrentlyReading()
        let filteredBooks = filterBooks(allBooks: allBooks, configuration: configuration)
        let entry = SimpleEntry(date: Date(), books: filteredBooks, configuration: configuration)

        let nextUpdate: Date
        if HardcoverConfig.apiKey.isEmpty || filteredBooks.isEmpty {
            nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        } else {
            nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        }
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    func recommendations() -> [AppIntentRecommendation<BookSelectionIntent>] {
        return []
    }
    
    private func filterBooks(allBooks: [BookProgress], configuration: BookSelectionIntent) -> [BookProgress] {
        if configuration.books.isEmpty {
            return allBooks
        }
        var filtered: [BookProgress] = []
        for selected in configuration.books {
            if let match = allBooks.first(where: { $0.id == selected.id }) {
                filtered.append(match)
            }
        }
        if filtered.isEmpty && !allBooks.isEmpty {
            return allBooks
        }
        return filtered
    }

    private func logDiagnostics(context: String) {
        let hasKey = !HardcoverConfig.apiKey.isEmpty
        let usesSuite = (AppGroup.defaults != .standard)
        let keyLength = HardcoverConfig.apiKey.count
        let ping = AppGroup.defaults.string(forKey: "WidgetPing") ?? "nil"
        print("🧪 Widget \(context): apiKey present? \(hasKey), length=\(keyLength), using App Group suite? \(usesSuite), ping=\(ping)")
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let books: [BookProgress]
    let configuration: BookSelectionIntent
}

struct ReadingProgressWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    var body: some View {
        let firstBook = entry.books.first
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
