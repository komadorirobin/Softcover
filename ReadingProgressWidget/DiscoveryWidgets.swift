import SwiftUI
import WidgetKit
import UIKit

private struct TrendingWidgetBook: Codable, Hashable, Identifiable {
    let id: Int
    let title: String
    let author: String
    let cover: Data?
}

private struct TrendingEntry: TimelineEntry {
    let date: Date
    let books: [TrendingWidgetBook]
}

private struct TrendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrendingEntry {
        TrendingEntry(date: Date(), books: [.init(id: 1, title: "Trending now", author: "Hardcover readers", cover: nil)])
    }
    func getSnapshot(in context: Context, completion: @escaping (TrendingEntry) -> Void) {
        Task { completion(await load()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendingEntry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3_600))))
        }
    }
    private func load() async -> TrendingEntry {
        let books = await HardcoverService.fetchTrendingBooksMonthly(limit: 4)
        var values: [TrendingWidgetBook] = []
        for book in books {
            var image: Data?
            if let value = book.coverImageUrl, let url = URL(string: value), let (data, _) = try? await URLSession.shared.data(from: url) { image = data }
            values.append(.init(id: book.id, title: book.title, author: book.author, cover: image))
        }
        return TrendingEntry(date: Date(), books: values)
    }
}

private struct TrendingWidgetView: View {
    let entry: TrendingEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Trending on Hardcover", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
            ForEach(entry.books.prefix(3)) { book in
                HStack(spacing: 9) {
                    Group {
                        if let data = book.cover, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
                        else { Color.secondary.opacity(0.15).overlay(Image(systemName: "book.closed")) }
                    }.frame(width: 30, height: 43).clipShape(RoundedRectangle(cornerRadius: 3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(book.title).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(book.author).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if entry.books.isEmpty { Text("Open Softcover to refresh trending books.").font(.caption).foregroundStyle(.secondary) }
        }.containerBackground(.fill.tertiary, for: .widget)
    }
}

struct TrendingBooksWidget: Widget {
    let kind = "TrendingBooksWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrendingProvider()) { TrendingWidgetView(entry: $0) }
            .configurationDisplayName("Trending Books")
            .description("See what Hardcover readers are picking up.")
            .supportedFamilies([.systemMedium])
    }
}

private struct RandomPickEntry: TimelineEntry { let date: Date; let book: BookProgress? }
private struct RandomPickProvider: TimelineProvider {
    func placeholder(in context: Context) -> RandomPickEntry { RandomPickEntry(date: Date(), book: nil) }
    func getSnapshot(in context: Context, completion: @escaping (RandomPickEntry) -> Void) { Task { completion(await load()) } }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RandomPickEntry>) -> Void) {
        Task {
            let entry = await load()
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
            completion(Timeline(entries: [entry], policy: .after(tomorrow)))
        }
    }
    private func load() async -> RandomPickEntry {
        var books = LibrarySnapshot.load(status: 1)?.books ?? []
        if books.isEmpty, let page = try? await LibraryAPI.page(status: 1, limit: 100) { books = page.books }
        guard !books.isEmpty else { return RandomPickEntry(date: Date(), book: nil) }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return RandomPickEntry(date: Date(), book: books[abs(day) % books.count])
    }
}

private struct RandomPickWidgetView: View {
    let entry: RandomPickEntry
    var body: some View {
        if let book = entry.book {
            VStack(spacing: 8) {
                BookCoverImage(url: book.coverImageUrl.flatMap(URL.init(string:)))
                    .frame(width: 58, height: 86).clipShape(RoundedRectangle(cornerRadius: 5))
                Text(book.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                Text("Today's random pick").font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).containerBackground(.fill.tertiary, for: .widget)
        } else {
            NoBooksView().containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct RandomBookWidget: Widget {
    let kind = "RandomBookWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RandomPickProvider()) { RandomPickWidgetView(entry: $0) }
            .configurationDisplayName("Random Book Pick")
            .description("A daily pick from your Want to Read shelf.")
            .supportedFamilies([.systemSmall])
    }
}
