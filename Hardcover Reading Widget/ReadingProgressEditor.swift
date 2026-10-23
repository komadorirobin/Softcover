import SwiftUI

struct ReadingProgressDraft {
    var units: Int
    let total: Int
    let isAudiobook: Bool

    init(book: BookProgress) {
        units = book.currentUnits
        total = book.totalUnits
        isAudiobook = book.isAudiobook
    }

    var isValid: Bool { units >= 0 && (total <= 0 || units <= total) }
    var percent: Double {
        get { total > 0 ? Double(units) / Double(total) * 100 : 0 }
        set { if total > 0 && newValue.isFinite { units = Int((Double(total) * min(100, max(0, newValue)) / 100).rounded()) } }
    }
}

struct ReadingProgressEditor: View {
    let book: BookProgress
    let onSaved: (BookProgress) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReadingProgressDraft
    @State private var usePercent = false
    @State private var saving = false
    @State private var error: String?
    @State private var changedBook: BookProgress?
    @State private var baselineUnits: Int
    @State private var backdate = false
    @State private var readAt = Date()
    private let authorization: String

    init(book: BookProgress, onSaved: @escaping (BookProgress) -> Void) {
        self.book = book
        self.onSaved = onSaved
        authorization = HardcoverConfig.accountIdentifier
        _draft = State(initialValue: ReadingProgressDraft(book: book))
        _baselineUnits = State(initialValue: book.currentUnits)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(book.title).font(.headline)
                    Text(BookProgressPresentation.summary(book)).foregroundStyle(.secondary)
                }
                Section("Reading progress") {
                    if draft.total > 0 {
                        Picker("Unit", selection: $usePercent) {
                            Text(book.isAudiobook ? LocalizedStringKey("Time") : LocalizedStringKey("Pages")).tag(false)
                            Text("Percent").tag(true)
                        }.pickerStyle(.segmented)
                    }
                    if usePercent {
                        Slider(value: $draft.percent, in: 0...100, step: 1) { Text("Percent") }
                        LabeledContent("Percent") {
                            TextField("Percent", value: $draft.percent, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(minWidth: 64, minHeight: 44)
                        }
                    } else if book.isAudiobook {
                        LabeledContent("Hours") {
                            TextField("Hours", value: hours, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(minHeight: 44)
                        }
                        LabeledContent("Minutes") {
                            TextField("Minutes", value: minutes, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(minHeight: 44)
                        }
                    } else {
                        LabeledContent("Page") {
                            TextField("Page", value: $draft.units, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(minHeight: 44)
                        }
                    }
                    Stepper(value: $draft.units, in: 0...max(draft.total > 0 ? draft.total : 1_000_000, 1)) {
                        Text(BookProgressPresentation.summary(book.withProgress(draft.units)))
                            .monospacedDigit()
                    }
                    if !draft.isValid {
                        Text("Progress must be within the edition's length.").foregroundStyle(.red)
                    }
                }
                Section("When did you read this?") {
                    Toggle("Choose a past date and time", isOn: $backdate)
                    if backdate {
                        DatePicker("Read at", selection: $readAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    } else {
                        Text("Just now").foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        if let changedBook {
                            Button("Use latest progress") {
                                draft = ReadingProgressDraft(book: changedBook)
                                baselineUnits = changedBook.currentUnits
                                self.changedBook = nil
                                self.error = nil
                            }.frame(minHeight: 44)
                        }
                    }
                }
            }
            .navigationTitle("Update progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Text("Save") }
                    }.disabled(saving || !draft.isValid || draft.units == baselineUnits)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private var hours: Binding<Int> {
        Binding(get: { draft.units / 60 }, set: { draft.units = max(0, min($0, 100_000)) * 60 + draft.units % 60 })
    }
    private var minutes: Binding<Int> {
        Binding(get: { draft.units % 60 }, set: { draft.units = draft.units / 60 * 60 + max(0, min(59, $0)) })
    }

    @MainActor private func save() async {
        guard !saving, draft.isValid else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            guard let bookID = book.bookId else { throw ReadingProgressWriter.Failure.missingBook }
            let request = ReadingProgressWriteRequest(bookID: bookID, userBookID: book.userBookId,
                editionID: book.editionId, expectedUnits: baselineUnits, totalUnits: draft.total,
                isAudiobook: draft.isAudiobook, units: draft.units, actionAt: backdate ? readAt : nil)
            let updated = try await OfflineWriteQueue.shared.performProgress(request, fallback: book)
            guard authorization == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            ReadingActivityStore.shared.recordProgress(book: updated, from: baselineUnits, to: draft.units,
                                                        at: backdate ? readAt : Date())
            WidgetSync.progressChanged(book: updated)
            onSaved(updated)
            dismiss()
        } catch {
            if case ReadingProgressWriter.Failure.progressChanged(let latest) = error { changedBook = latest }
            else if case ReadingProgressWriter.Failure.editionChanged(_) = error { changedBook = nil }
            self.error = error.localizedDescription
        }
    }
}
