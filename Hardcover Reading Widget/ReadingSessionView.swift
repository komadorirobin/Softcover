import SwiftUI

struct ReadingSessionView: View {
    let book: BookProgress
    var onProgressSaved: ((BookProgress) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activity = ReadingActivityStore.shared
    @State private var endingUnits: Int
    @State private var working = false
    @State private var error: String?
    private let authorization: String

    init(book: BookProgress, onProgressSaved: ((BookProgress) -> Void)? = nil) {
        self.book = book
        self.onProgressSaved = onProgressSaved
        authorization = HardcoverConfig.accountIdentifier
        _endingUnits = State(initialValue: book.currentUnits)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = activity.activeSession {
                    if session.bookID == book.bookId { activeContent(session) }
                    else {
                        ContentUnavailableView {
                            Label("Another session is active", systemImage: "timer")
                        } description: {
                            Text("End the session for “\(session.title)” before starting a new one.")
                        }
                    }
                } else { startContent }
            }
            .navigationTitle("Reading session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(working) }
            }
            .alert("Could not save session", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var startContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "timer").font(.system(size: 54)).foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text(book.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                if !book.author.isEmpty { Text(book.author).foregroundStyle(.secondary) }
            }
            Text("Track focused reading time. The timer continues in the Live Activity when you leave Softcover.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                endingUnits = book.currentUnits
                _ = activity.startSession(for: book)
            } label: {
                Label("Start session", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }

    private func activeContent(_ session: ActiveReadingSession) -> some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Text(session.title).font(.headline).multilineTextAlignment(.center)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.duration(session.elapsed(at: context.date)))
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    Text(session.isRunning ? LocalizedStringKey("Reading now") : LocalizedStringKey("Paused"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)

                Button {
                    if session.isRunning { activity.pauseSession() } else { activity.resumeSession() }
                } label: {
                    Label(session.isRunning ? "Pause" : "Resume",
                          systemImage: session.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }

            Section("Progress at end") {
                Stepper(value: $endingUnits, in: session.startingUnits...(session.totalUnits > 0
                    ? max(session.startingUnits, session.totalUnits) : session.startingUnits + 100_000)) {
                    Text(progressSummary(session: session)).monospacedDigit()
                }
                if session.totalUnits > session.startingUnits {
                    Slider(value: Binding(get: { Double(endingUnits) }, set: { endingUnits = Int($0.rounded()) }),
                           in: Double(session.startingUnits)...Double(max(session.startingUnits, session.totalUnits)), step: 1)
                }
            }

            if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }

            Section {
                Button {
                    Task { await finish(session) }
                } label: {
                    if working { ProgressView().frame(maxWidth: .infinity) }
                    else { Label("End session", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44) }
                }
                .buttonStyle(.borderedProminent).disabled(working)
            }
        }
        .interactiveDismissDisabled(working)
    }

    @MainActor private func finish(_ session: ActiveReadingSession) async {
        guard !working else { return }
        working = true; error = nil
        defer { working = false }
        do {
            var updated: BookProgress?
            if endingUnits != session.startingUnits {
                let request = ReadingProgressWriteRequest(bookID: session.bookID, userBookID: session.userBookID,
                    editionID: session.editionID, expectedUnits: session.startingUnits, totalUnits: session.totalUnits,
                    isAudiobook: session.isAudiobook, units: endingUnits, actionAt: nil)
                updated = try await OfflineWriteQueue.shared.performProgress(request, fallback: book)
                guard authorization == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            }
            activity.stopSession(endingUnits: endingUnits)
            if let updated {
                WidgetSync.progressChanged(book: updated)
                onProgressSaved?(updated)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func progressSummary(session: ActiveReadingSession) -> String {
        if session.isAudiobook {
            let current = BookProgressPresentation.duration(endingUnits)
            return session.totalUnits > 0 ? "\(current) of \(BookProgressPresentation.duration(session.totalUnits))" : current
        }
        return session.totalUnits > 0 ? "Page \(endingUnits) of \(session.totalUnits)" : "Page \(endingUnits)"
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}
