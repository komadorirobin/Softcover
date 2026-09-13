import SwiftUI

struct SearchResultDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let book: BookProgress
    let onAddComplete: (Bool) -> Void

    var body: some View {
        NavigationStack {
            BookDetailView(book: book, onLibraryChange: { _ in onAddComplete(true) })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
        }
    }
}
