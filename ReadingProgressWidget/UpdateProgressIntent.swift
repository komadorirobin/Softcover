import AppIntents
import WidgetKit
import SwiftUI

struct IncrementReadingProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Update Reading Progress"
    static var description = IntentDescription("Adds pages or listening minutes to a currently reading book.")
    static var openAppWhenRun = false

    @Parameter(title: "Book ID") var bookID: Int
    @Parameter(title: "Amount") var amount: Int

    init() { bookID = 0; amount = 10 }
    init(bookID: Int, amount: Int) { self.bookID = bookID; self.amount = amount }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard bookID > 0 else { return .result(dialog: "The book is no longer available.") }
        do {
            let updated = try await ReadingProgressWriter.increment(bookID: bookID, amount: amount)
            WidgetSync.progressChanged(book: updated)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSync.readingKind)
            return .result(dialog: "Progress updated.")
        } catch {
            return .result(dialog: "Progress could not be updated. Open Softcover and try again.")
        }
    }
}

struct WidgetProgressButton: View {
    let book: BookProgress
    var body: some View {
        if let id = book.bookId, book.userBookId != nil {
            Button(intent: IncrementReadingProgressIntent(bookID: id, amount: book.isAudiobook ? 15 : 10)) {
                Image(systemName: "plus").font(.caption.bold()).frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .accessibilityLabel(book.isAudiobook ? "Add 15 minutes" : "Add 10 pages")
        }
    }
}
