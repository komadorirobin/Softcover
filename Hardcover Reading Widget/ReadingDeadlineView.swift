import SwiftUI

enum ReadingPacePresentation {
    static func summary(book: BookProgress, deadline: ReadingDeadline?, now: Date = Date(),
                        calendar: Calendar = .current) -> String? {
        guard let deadline, book.totalUnits > 0 else { return nil }
        guard let units = deadline.unitsPerDay(currentUnits: book.currentUnits, totalUnits: book.totalUnits,
                                               now: now, calendar: calendar) else {
            return NSLocalizedString("Reading deadline passed", comment: "")
        }
        if units == 0 { return NSLocalizedString("Reading target complete", comment: "") }
        if book.isAudiobook {
            return String(format: NSLocalizedString("%@ per day", comment: ""), BookProgressPresentation.duration(units))
        }
        return String(format: NSLocalizedString("%d pages per day", comment: ""), units)
    }
}

struct ReadingDeadlineView: View {
    let book: BookProgress
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activity = ReadingActivityStore.shared
    @State private var targetDate: Date

    init(book: BookProgress) {
        self.book = book
        let existing = book.bookId.flatMap { ReadingActivityStore.shared.deadline(for: $0) }?.targetDate
        let today = Calendar.current.startOfDay(for: Date())
        _targetDate = State(initialValue: max(existing ?? Calendar.current.date(byAdding: .day, value: 30, to: today)!, today))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(book.title).font(.headline)
                    DatePicker("Finish by", selection: $targetDate, in: Calendar.current.startOfDay(for: Date())...,
                               displayedComponents: .date)
                }
                if let bookID = book.bookId {
                    Section("Daily pace") {
                        let deadline = ReadingDeadline(bookID: bookID, targetDate: targetDate, createdAt: Date())
                        if let pace = ReadingPacePresentation.summary(book: book, deadline: deadline) {
                            Label(pace, systemImage: "figure.walk")
                        }
                        Text("Softcover recalculates the pace whenever you update your progress.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if activity.deadline(for: bookID) != nil {
                        Section {
                            Button("Remove deadline", role: .destructive) {
                                activity.removeDeadline(for: bookID)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reading deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let bookID = book.bookId else { return }
                        activity.setDeadline(for: bookID, targetDate: targetDate)
                        dismiss()
                    }
                }
            }
        }
    }
}
