import SwiftUI

struct ReadingSessionHistoryView: View {
    @ObservedObject private var activity = ReadingActivityStore.shared
    @State private var editingSession: ReadingSessionRecord?
    @State private var pendingDeletion: ReadingSessionRecord?

    private var sessions: [ReadingSessionRecord] {
        activity.sessions.sorted {
            if $0.endedAt != $1.endedAt { return $0.endedAt > $1.endedAt }
            return $0.startedAt > $1.startedAt
        }
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Reading Sessions", systemImage: "timer")
                } description: {
                    Text("Completed sessions will appear here after you stop the reading timer.")
                }
            } else {
                List {
                    Section {
                        ForEach(sessions) { session in
                            Button { editingSession = session } label: {
                                ReadingSessionHistoryRow(session: session)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { pendingDeletion = session }
                                Button("Edit") { editingSession = session }.tint(.indigo)
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editingSession = session }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDeletion = session
                                }
                            }
                        }
                    } footer: {
                        Text("Sessions are stored on this device. Editing or deleting one changes Softcover statistics, not progress already saved to Hardcover.")
                    }
                }
            }
        }
        .navigationTitle("Reading Sessions")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editingSession) { session in
            ReadingSessionEditor(session: session) { corrected in
                _ = activity.updateSession(corrected)
            }
        }
        .confirmationDialog("Delete Reading Session?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion { _ = activity.deleteSession(id: pendingDeletion.id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the session from Softcover statistics. Progress already saved to Hardcover will not change.")
        }
    }
}

private struct ReadingSessionHistoryRow: View {
    let session: ReadingSessionRecord

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: session.isAudiobook ? "headphones" : "book.closed.fill")
                .font(.title3)
                .foregroundStyle(session.isAudiobook ? .orange : .indigo)
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(Self.dateAndTime(session.startedAt))
                    .font(.caption).foregroundStyle(.secondary)
                if session.progressedUnits > 0 {
                    Label(progressText, systemImage: "arrow.up.right")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No progress recorded").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(Self.duration(session.durationSeconds))
                .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens session editor")
    }

    private var progressText: String {
        if session.isAudiobook {
            return "+\(BookProgressPresentation.duration(session.progressedUnits))"
        }
        return "+\(session.progressedUnits) "
            + NSLocalizedString(session.progressedUnits == 1 ? "page" : "pages", comment: "")
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return String(format: "%dh %02dm", seconds / 3_600, (seconds / 60) % 60)
    }

    private static func dateAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ReadingSessionEditor: View {
    let session: ReadingSessionRecord
    let onSave: (ReadingSessionRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var startingUnits: Int
    @State private var endingUnits: Int

    init(session: ReadingSessionRecord, onSave: @escaping (ReadingSessionRecord) -> Void) {
        self.session = session
        self.onSave = onSave
        let total = max(0, Int(session.durationSeconds.rounded()))
        _startedAt = State(initialValue: session.startedAt)
        _endedAt = State(initialValue: session.endedAt)
        _hours = State(initialValue: total / 3_600)
        _minutes = State(initialValue: (total / 60) % 60)
        _seconds = State(initialValue: total % 60)
        _startingUnits = State(initialValue: session.startingUnits)
        _endingUnits = State(initialValue: session.endingUnits)
    }

    private var durationSeconds: TimeInterval {
        TimeInterval(max(0, hours) * 3_600 + max(0, minutes) * 60 + max(0, seconds))
    }

    private var validationMessage: LocalizedStringKey? {
        if endedAt < startedAt { return "The end must be after the start." }
        if durationSeconds <= 0 { return "Focused time must be longer than zero." }
        if durationSeconds > endedAt.timeIntervalSince(startedAt) + 1 {
            return "Focused time cannot be longer than the session."
        }
        if hours < 0 || minutes < 0 || minutes > 59 || seconds < 0 || seconds > 59 {
            return "Enter a valid duration."
        }
        if startingUnits < 0 || endingUnits < startingUnits {
            return session.isAudiobook ? "The ending minute must not be before the starting minute."
                : "The ending page must not be before the starting page."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    LabeledContent("Book", value: session.title)
                    DatePicker("Started", selection: $startedAt)
                    DatePicker("Ended", selection: $endedAt)
                }

                Section("Focused Time") {
                    HStack(spacing: 8) {
                        durationField("Hours", value: $hours)
                        durationField("Minutes", value: $minutes)
                        durationField("Seconds", value: $seconds)
                    }
                }

                Section {
                    TextField(startingUnitsLabel, value: $startingUnits, format: .number)
                        .keyboardType(.numberPad)
                    TextField(endingUnitsLabel, value: $endingUnits, format: .number)
                        .keyboardType(.numberPad)
                } header: {
                    Text(progressSectionTitle)
                }

                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(.red) }
                }

                Section {
                    Text("This changes Softcover’s local history and statistics only. Your current Hardcover progress is not changed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(validationMessage != nil)
                }
            }
        }
    }

    private func durationField(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
        }
    }

    private var progressSectionTitle: LocalizedStringKey {
        session.isAudiobook ? "Listening Progress" : "Reading Progress"
    }

    private var startingUnitsLabel: LocalizedStringKey {
        session.isAudiobook ? "Starting minute" : "Starting page"
    }

    private var endingUnitsLabel: LocalizedStringKey {
        session.isAudiobook ? "Ending minute" : "Ending page"
    }

    private func save() {
        guard let corrected = session.corrected(
            startedAt: startedAt, endedAt: endedAt, durationSeconds: durationSeconds,
            startingUnits: startingUnits, endingUnits: endingUnits
        ) else { return }
        onSave(corrected)
        dismiss()
    }
}
