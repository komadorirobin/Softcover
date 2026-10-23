import SwiftUI

struct FinishRateReviewSheet: View {
    let book: BookProgress
    let markFinished: Bool
    let onSaved: (BookProgress) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Double
    @State private var ratingChanged = false
    @State private var reviewText = ""
    @State private var hasSpoilers = false
    @State private var working = false
    @State private var error: String?
    @State private var publishedDraft: String?
    @State private var confirmDiscard = false
    @State private var backdate = false
    @State private var finishedAt = Date()
    private let authorization: String

    init(book: BookProgress, markFinished: Bool, onSaved: @escaping (BookProgress) -> Void) {
        self.book = book
        self.markFinished = markFinished
        self.onSaved = onSaved
        authorization = HardcoverConfig.accountIdentifier
        _rating = State(initialValue: book.userRating ?? 0)
    }

    private var dirty: Bool { ratingChanged || !reviewText.isEmpty || backdate }
    private var draftKey: String { "\(hasSpoilers):\(reviewText.trimmingCharacters(in: .whitespacesAndNewlines))" }
    private var selectedRating: Double? { rating > 0 ? rating : nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(book.title).font(.headline)
                    Label(book.displayFormat, systemImage: book.isAudiobook ? "headphones" : "book.closed")
                        .foregroundStyle(.secondary)
                }
                Section("Rating") {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                rating = Double(star); ratingChanged = true
                            } label: {
                                Image(systemName: rating >= Double(star) ? "star.fill" : rating >= Double(star) - 0.5 ? "star.leadinghalf.filled" : "star")
                                    .font(.title2).foregroundStyle(.orange).frame(minWidth: 44, minHeight: 44)
                            }.buttonStyle(.borderless)
                                .accessibilityLabel(Text("\(star) of 5 stars"))
                        }
                    }
                    Slider(value: Binding(get: { rating }, set: { rating = $0; ratingChanged = true }), in: 0...5, step: 0.5) {
                        Text("Rating")
                    }.accessibilityValue(Text("\(rating, specifier: "%.1f") of 5"))
                    Text("Rating: \(rating, specifier: "%.1f")").monospacedDigit().foregroundStyle(.secondary)
                }
                Section("Review (optional)") {
                    TextEditor(text: $reviewText).frame(minHeight: 160).accessibilityLabel("Review")
                    Toggle("Contains spoilers", isOn: $hasSpoilers)
                    if publishedDraft == draftKey {
                        Label("Published", systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                    Button { Task { await publishOnly() } } label: {
                        Label("Publish review", systemImage: "paperplane").frame(minHeight: 44)
                    }.disabled(working || reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || publishedDraft == draftKey
                               || (markFinished && book.userBookId == nil))
                }
                if markFinished {
                    Section("Finished") {
                        Toggle("Choose a past date and time", isOn: $backdate)
                        if backdate {
                            DatePicker("Finished at", selection: $finishedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        } else {
                            Text("Just now").foregroundStyle(.secondary)
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                if markFinished && !reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Button("Finish without review") { Task { await save(includeReview: false) } }
                            .frame(minHeight: 44).disabled(working)
                    }
                }
            }
            .navigationTitle(markFinished ? LocalizedStringKey("Mark as finished") : LocalizedStringKey("Rate and review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if dirty { confirmDiscard = true } else { dismiss() }
                    }.disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save(includeReview: true) } } label: {
                        if working { ProgressView() }
                        else { Text(markFinished ? LocalizedStringKey("Finish") : LocalizedStringKey("Save")) }
                    }.disabled(working || (!markFinished && !dirty))
                }
            }
            .interactiveDismissDisabled(working || dirty)
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            }
        }
    }

    @MainActor private func publish(own: BookProgress) async throws {
        let text = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, publishedDraft != draftKey else { return }
        guard authorization == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
        guard let id = own.userBookId,
              await OfflineWriteQueue.shared.perform(.review(userBookID: id, text: text, spoilers: hasSpoilers)) else {
            throw BookPersonalActions.Failure.saveFailed
        }
        publishedDraft = draftKey
    }

    @MainActor private func publishOnly() async {
        guard !working else { return }
        working = true; error = nil
        defer { working = false }
        do {
            let own = try await BookPersonalActions.requireOwnBook(bookID: book.bookId, authorization: authorization)
            try await publish(own: own)
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func save(includeReview: Bool) async {
        guard !working else { return }
        working = true; error = nil
        defer { working = false }
        do {
            if markFinished {
                try await completeBook(includeReview: includeReview)
                return
            }
            var own = try await BookPersonalActions.requireOwnBook(bookID: book.bookId, authorization: authorization)
            guard let id = own.userBookId else { throw BookPersonalActions.Failure.missingBook }
            if includeReview { try await publish(own: own) }
            guard authorization == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            if ratingChanged {
                guard await OfflineWriteQueue.shared.perform(.rating(userBookID: id, value: selectedRating)) else {
                    throw BookPersonalActions.Failure.saveFailed
                }
                own.userRating = selectedRating
            }
            guard authorization == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            WidgetSync.libraryChanged(statuses: [own.statusId ?? 3])
            guard authorization == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            onSaved(own)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func completeBook(includeReview: Bool) async throws {
        guard let bookID = book.bookId else { throw BookPersonalActions.Failure.missingBook }
        let targetUnits = book.totalUnits > 0 ? book.totalUnits : book.currentUnits
        let review = includeReview && publishedDraft != draftKey
            ? reviewText.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let operation = OfflineWriteOperation.complete(bookID: bookID, userBookID: book.userBookId,
            editionID: book.editionId, targetUnits: targetUnits, audiobook: book.isAudiobook,
            totalPages: !book.isAudiobook && book.totalPages > 0 ? book.totalPages : nil,
            currentPage: !book.isAudiobook && targetUnits > 0 ? targetUnits : nil,
            actionAt: backdate ? finishedAt : nil, ratingChanged: ratingChanged,
            rating: selectedRating, review: review, spoilers: hasSpoilers)
        guard await OfflineWriteQueue.shared.perform(operation) else { throw BookPersonalActions.Failure.saveFailed }
        guard authorization == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
        var updated = book.withProgress(targetUnits)
        if ratingChanged { updated.userRating = selectedRating }
        let oldStatus = updated.statusId ?? 2
        updated.statusId = 3
        ReadingActivityStore.shared.recordFinished(book: updated, from: book.currentUnits,
                                                    at: backdate ? finishedAt : Date())
        WidgetSync.libraryChanged(statuses: [oldStatus, 3])
        onSaved(updated)
        dismiss()
    }
}
