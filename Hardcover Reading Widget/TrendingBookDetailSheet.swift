import SwiftUI

struct TrendingBookDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: HardcoverService.TrendingBook
    let isWorking: Bool
    let onAddWithEdition: (Int?) -> Void

    var body: some View {
        NavigationStack {
            BookDetailView(book: BookProgress(id: "book-\(item.id)", title: item.title, author: item.author,
                coverImageUrl: item.coverImageUrl, bookId: item.id, originalTitle: item.title),
                onAddToWantToRead: onAddWithEdition)
                .disabled(isWorking)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
        }
    }
}
