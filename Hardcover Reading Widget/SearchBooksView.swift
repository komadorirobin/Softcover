import SwiftUI

struct SearchBooksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var titleQuery: String = ""
    @State private var authorQuery: String = ""
    @State private var isSearching = false
    @State private var results: [HydratedBook] = []
    @State private var addInProgressForId: Int?
    @State private var errorMessage: String?

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Book title", text: $titleQuery, onCommit: { Task { await runSearch() } })
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    HStack {
                        Image(systemName: "person").foregroundColor(.secondary)
                        TextField("Author (optional)", text: $authorQuery, onCommit: { Task { await runSearch() } })
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    Button(action: { Task { await runSearch() } }) {
                        HStack {
                            if isSearching { ProgressView().scaleEffect(0.8) }
                            Text(isSearching ? "Searching…" : "Search")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSearching || titleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                if results.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("Search Hardcover for books")
                            .foregroundColor(.secondary)
                            .font(.headline)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(results) { book in
                            Button(action: { Task { await addBook(book) } }) {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 36, height: 52)
                                        .overlay(Image(systemName: "book").foregroundColor(.secondary))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(book.title).font(.subheadline).lineLimit(2)
                                        let author = book.contributions?.first?.author?.name ?? "Unknown Author"
                                        Text(author).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if addInProgressForId == book.id {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "plus.circle.fill").foregroundColor(.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(addInProgressForId != nil)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func runSearch() async {
        errorMessage = nil
        let title = titleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = authorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isSearching = true
        let list = await HardcoverService.searchBooks(title: title, author: author.isEmpty ? nil : author)
        await MainActor.run {
            self.results = list
            self.isSearching = false
            if list.isEmpty {
                self.errorMessage = "No results. Try another title or author."
            }
        }
    }

    private func addBook(_ book: HydratedBook) async {
        addInProgressForId = book.id
        let ok = await HardcoverService.addBookToCurrentlyReading(bookId: book.id, editionId: nil)
        await MainActor.run {
            addInProgressForId = nil
            if ok {
                onDone(true)
                dismiss()
            } else {
                errorMessage = "Failed to add book. Check API key and try again."
            }
        }
    }
}

#Preview { SearchBooksView { _ in } }
