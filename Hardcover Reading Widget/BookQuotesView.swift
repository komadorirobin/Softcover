import SwiftUI
import WidgetKit

/// View for listing, adding, editing, and deleting quotes for a specific book.
struct BookQuotesView: View {
    let bookId: Int
    let bookTitle: String
    let editionId: Int?
    let totalPages: Int?

    /// Optional: if set, this specific quote will be highlighted/scrolled to on appear
    var highlightQuoteId: Int? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var quotes: [Quote] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var editingQuote: Quote? = nil
    @State private var deletingQuote: Quote? = nil
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading quotes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if quotes.isEmpty {
                    emptyStateView
                } else {
                    quotesListView
                }
            }
            .navigationTitle("Quotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Quote")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                QuoteEditorSheet(
                    mode: .add,
                    bookId: bookId,
                    editionId: editionId,
                    totalPages: totalPages,
                    existingEntry: "",
                    existingPage: nil
                ) { success in
                    if success {
                        Task { await loadQuotes() }
                        WidgetCenter.shared.reloadTimelines(ofKind: "QuoteWidget")
                    }
                }
            }
            .sheet(item: $editingQuote) { quote in
                QuoteEditorSheet(
                    mode: .edit(quoteId: quote.id),
                    bookId: bookId,
                    editionId: editionId,
                    totalPages: totalPages,
                    existingEntry: quote.entry,
                    existingPage: quote.page
                ) { success in
                    if success {
                        Task { await loadQuotes() }
                        WidgetCenter.shared.reloadTimelines(ofKind: "QuoteWidget")
                    }
                }
            }
            .alert("Delete Quote?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    guard let quote = deletingQuote else { return }
                    Task { await performDelete(quoteId: quote.id) }
                }
                Button("Cancel", role: .cancel) {
                    deletingQuote = nil
                }
            } message: {
                Text("This will permanently remove the quote.")
            }
            .task {
                await loadQuotes()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "quote.opening")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Quotes Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add your favourite quotes from this book.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAddSheet = true
            } label: {
                Label("Add Quote", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Quotes List

    private var quotesListView: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(quotes) { quote in
                    QuoteRowView(
                        quote: quote,
                        isHighlighted: quote.id == highlightQuoteId,
                        onEdit: { editingQuote = quote },
                        onDelete: {
                            deletingQuote = quote
                            showDeleteConfirmation = true
                        }
                    )
                    .id(quote.id)
                }
            }
            .listStyle(.plain)
            .onAppear {
                if let targetId = highlightQuoteId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo(targetId, anchor: .center)
                        }
                    }
                }
            }
            .overlay {
                if isDeleting {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    ProgressView("Deleting…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadQuotes() async {
        await MainActor.run { isLoading = true }
        let fetched = await HardcoverService.fetchQuotesForBook(bookId: bookId)
        await MainActor.run {
            quotes = fetched
            isLoading = false
        }
    }

    private func performDelete(quoteId: Int) async {
        await MainActor.run { isDeleting = true }
        let success = await HardcoverService.deleteQuote(quoteId: quoteId)
        if success {
            await MainActor.run {
                quotes.removeAll { $0.id == quoteId }
                isDeleting = false
                deletingQuote = nil
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "QuoteWidget")
        } else {
            await MainActor.run {
                isDeleting = false
                errorMessage = "Failed to delete quote."
            }
        }
    }
}

// MARK: - Quote Row

struct QuoteRowView: View {
    let quote: Quote
    var isHighlighted: Bool = false
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 3)

                Text(quote.entry)
                    .font(.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !quote.createdAt.isEmpty || quote.page != nil {
                HStack(spacing: 8) {
                    if let page = quote.page {
                        Label("Page \(page)", systemImage: "book")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if !quote.createdAt.isEmpty {
                        Text(formattedDate(quote.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = quote.entry
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        // The API returns microsecond precision (e.g. "2026-02-07T11:17:17.996714")
        // which ISO8601DateFormatter can't handle. Use DateFormatter with explicit format.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)

        // Try with fractional seconds (trim to milliseconds if needed)
        let trimmed = truncateFractionalSeconds(dateString)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = df.date(from: dateString) {
            return displayFormatter.string(from: date)
        }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let date = df.date(from: trimmed) {
            return displayFormatter.string(from: date)
        }
        // Without fractional seconds
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = df.date(from: dateString.components(separatedBy: ".").first ?? dateString) {
            return displayFormatter.string(from: date)
        }

        // ISO8601 full format fallback
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        return dateString
    }

    private var displayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    /// Truncate fractional seconds to 3 digits (milliseconds) for DateFormatter compatibility
    private func truncateFractionalSeconds(_ s: String) -> String {
        guard let dotRange = s.range(of: ".") else { return s }
        let afterDot = s[dotRange.upperBound...]
        // Find where digits end (could be followed by Z, +, - or nothing)
        let digits = afterDot.prefix(while: { $0.isNumber })
        if digits.count > 3 {
            let ms = digits.prefix(3)
            let rest = s[afterDot.index(afterDot.startIndex, offsetBy: digits.count)...]
            return String(s[..<dotRange.upperBound]) + ms + rest
        }
        return s
    }
}

// MARK: - Quote Editor Sheet (Add / Edit)

struct QuoteEditorSheet: View {
    enum Mode {
        case add
        case edit(quoteId: Int)
    }

    let mode: Mode
    let bookId: Int
    let editionId: Int?
    let totalPages: Int?
    let existingEntry: String
    let existingPage: Int?
    let onComplete: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entryText: String = ""
    @State private var pageText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var parsedPage: Int? {
        let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private var title: String {
        switch mode {
        case .add: return "Add Quote"
        case .edit: return "Edit Quote"
        }
    }

    private var canSave: Bool {
        !entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $entryText)
                        .frame(minHeight: 150)
                        .font(.body)
                } header: {
                    Text("Quote Text")
                }

                Section {
                    HStack {
                        Text("Page")
                            .foregroundColor(.secondary)
                        TextField("", text: $pageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        if let total = totalPages, total > 0 {
                            Text("of \(total)")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Page Number")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Optional – the page this quote is from.")
                            .foregroundColor(.secondary)
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                entryText = existingEntry
                if let page = existingPage {
                    pageText = "\(page)"
                }
            }
            .interactiveDismissDisabled(isSaving)
            .overlay {
                if isSaving {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                    ProgressView("Saving…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func save() async {
        let trimmed = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            isSaving = true
            errorMessage = nil
        }

        let success: Bool
        switch mode {
        case .add:
            success = await HardcoverService.createQuote(
                bookId: bookId,
                editionId: editionId,
                entry: trimmed,
                page: parsedPage,
                totalPages: totalPages
            )
        case .edit(let quoteId):
            success = await HardcoverService.updateQuote(
                quoteId: quoteId,
                entry: trimmed
            )
        }

        await MainActor.run {
            isSaving = false
            if success {
                onComplete(true)
                dismiss()
            } else {
                errorMessage = "Failed to save. Please try again."
            }
        }
    }
}
