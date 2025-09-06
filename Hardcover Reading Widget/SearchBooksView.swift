import SwiftUI

struct SearchBooksView: View {
    enum Destination: String, CaseIterable, Identifiable {
        case currentlyReading = "Currently Reading"
        case wantToRead = "Want to Read"
        var id: String { rawValue }
        
        var buttonTitle: String {
            switch self {
            case .currentlyReading: return NSLocalizedString("Add to Currently Reading", comment: "")
            case .wantToRead: return NSLocalizedString("Add to Want to Read", comment: "")
            }
        }
        
        var iconName: String {
            switch self {
            case .currentlyReading: return "book.fill"
            case .wantToRead: return "bookmark.fill"
            }
        }
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var isSearching = false
    @State private var results: [HydratedBook] = []
    @State private var addInProgressForId: Int?
    @State private var errorMessage: String?
    
    @State private var destination: Destination = .currentlyReading

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    // Destination picker
                    Picker("Destination", selection: $destination) {
                        Text("Currently Reading").tag(Destination.currentlyReading)
                        Text("Want to Read").tag(Destination.wantToRead)
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Title or author (tip: author:Herbert)", text: $query, onCommit: { Task { await runSearch() } })
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .accessibilityLabel("Search books")
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
                    .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                                        Label(destination.buttonTitle, systemImage: destination.iconName)
                                            .labelStyle(.iconOnly)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(addInProgressForId != nil)
                            .accessibilityLabel(destination.buttonTitle)
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
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let (titlePart, authorPart) = parseQuery(raw)
        
        isSearching = true
        // Skicka separat title + author om vi hittade en explicit author:-tagg.
        // Annars skickar vi hela strängen som title och author=nil (t.ex. “dune herbert”).
        let list = await HardcoverService.searchBooks(
            title: titlePart,
            author: authorPart?.isEmpty == false ? authorPart : nil
        )
        await MainActor.run {
            self.results = list
            self.isSearching = false
            if list.isEmpty {
                self.errorMessage = "No results. Try another search."
            }
        }
    }
    
    // Enkel parser för “author:” (case-insensitive).
    // Stödjer: author:Herbert och author:"Frank Herbert"
    // - Tar bort author:-delen från titeln
    // - Resterande används som title
    private func parseQuery(_ q: String) -> (title: String, author: String?) {
        let lower = q.lowercased()
        guard let range = lower.range(of: "author:") else {
            // Ingen explicit author: -> allt som title, ingen author
            return (q, nil)
        }
        // Dela upp i prefix (title-del) och suffix (efter "author:")
        let authorStartIndex = range.upperBound
        let titlePart = q[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let authorRaw = q[authorStartIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Om författaren är citerad, plocka innehållet i första citationsteckens-par
        if authorRaw.hasPrefix("\"") {
            if let endQuote = authorRaw.dropFirst().firstIndex(of: "\"") {
                let name = authorRaw[authorRaw.index(after: authorRaw.startIndex)..<endQuote]
                return (titlePart, String(name).trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                // Ingen avslutande citation – ta resten som author
                return (titlePart, String(authorRaw.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            // Ta hela suffixet som author (till slutet av strängen)
            return (titlePart, authorRaw)
        }
    }

    private func addBook(_ book: HydratedBook) async {
        addInProgressForId = book.id
        let ok: Bool
        switch destination {
        case .currentlyReading:
            ok = await HardcoverService.addBookToCurrentlyReading(bookId: book.id, editionId: nil)
        case .wantToRead:
            ok = await HardcoverService.addBookToWantToRead(bookId: book.id, editionId: nil)
        }
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
