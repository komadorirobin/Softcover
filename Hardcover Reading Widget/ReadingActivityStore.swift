import ActivityKit
import Combine
import CryptoKit
import Foundation

private struct ReadingActivityArchive: Codable {
    var deadlines: [ReadingDeadline] = []
    var activeSession: ActiveReadingSession?
    var sessions: [ReadingSessionRecord] = []
    var events: [ReadingActivityEvent] = []
}

@MainActor
final class ReadingActivityStore: ObservableObject {
    static let shared = ReadingActivityStore()

    @Published private(set) var deadlines: [ReadingDeadline] = []
    @Published private(set) var activeSession: ActiveReadingSession?
    @Published private(set) var sessions: [ReadingSessionRecord] = []
    @Published private(set) var events: [ReadingActivityEvent] = []

    private var storageKey = ""

    private init() { reload() }

    var metrics: ReadingActivityMetrics {
        ReadingActivityMetrics.calculate(events: events, sessions: sessions)
    }

    func reload() {
        let newKey = Self.key(for: HardcoverConfig.accountIdentifier)
        guard newKey != storageKey else { return }
        if activeSession != nil { Task { await ReadingSessionLiveActivity.end() } }
        storageKey = newKey
        guard let data = AppGroup.defaults.data(forKey: newKey),
              let archive = try? JSONDecoder().decode(ReadingActivityArchive.self, from: data) else {
            deadlines = []; activeSession = nil; sessions = []; events = []
            return
        }
        deadlines = archive.deadlines
        activeSession = archive.activeSession
        sessions = archive.sessions
        events = archive.events
        if let activeSession { Task { await ReadingSessionLiveActivity.startOrUpdate(activeSession) } }
    }

    func deadline(for bookID: Int?) -> ReadingDeadline? {
        guard let bookID else { return nil }
        return deadlines.first { $0.bookID == bookID }
    }

    func setDeadline(for bookID: Int, targetDate: Date) {
        deadlines.removeAll { $0.bookID == bookID }
        deadlines.append(ReadingDeadline(bookID: bookID, targetDate: targetDate, createdAt: Date()))
        persist()
    }

    func removeDeadline(for bookID: Int) {
        deadlines.removeAll { $0.bookID == bookID }
        persist()
    }

    @discardableResult
    func startSession(for book: BookProgress, at date: Date = Date()) -> Bool {
        guard activeSession == nil, let bookID = book.bookId else { return false }
        let session = ActiveReadingSession(
            id: UUID(), bookID: bookID, userBookID: book.userBookId, editionID: book.editionId,
            title: book.title, author: book.author, isAudiobook: book.isAudiobook,
            totalUnits: book.totalUnits, startingUnits: book.currentUnits,
            accumulatedSeconds: 0, resumedAt: date, startedAt: date
        )
        activeSession = session
        persist()
        Task { await ReadingSessionLiveActivity.startOrUpdate(session) }
        return true
    }

    func pauseSession(at date: Date = Date()) {
        guard var session = activeSession else { return }
        session.pause(at: date)
        activeSession = session
        persist()
        Task { await ReadingSessionLiveActivity.startOrUpdate(session) }
    }

    func resumeSession(at date: Date = Date()) {
        guard var session = activeSession else { return }
        session.resume(at: date)
        activeSession = session
        persist()
        Task { await ReadingSessionLiveActivity.startOrUpdate(session) }
    }

    func stopSession(endingUnits: Int, at date: Date = Date()) {
        guard var session = activeSession else { return }
        session.pause(at: date)
        let finalUnits = max(session.startingUnits, session.totalUnits > 0 ? min(endingUnits, session.totalUnits) : endingUnits)
        sessions.append(ReadingSessionRecord(
            id: session.id, bookID: session.bookID, title: session.title, isAudiobook: session.isAudiobook,
            startedAt: session.startedAt, endedAt: date, durationSeconds: session.accumulatedSeconds,
            startingUnits: session.startingUnits, endingUnits: finalUnits
        ))
        events.append(ReadingActivityEvent(
            id: UUID(), bookID: session.bookID, date: date, kind: .session, sessionID: session.id,
            unitDelta: max(0, finalUnits - session.startingUnits), isAudiobook: session.isAudiobook
        ))
        activeSession = nil
        trimAndPersist()
        Task { await ReadingSessionLiveActivity.end(session: session, currentUnits: finalUnits) }
    }

    @discardableResult
    func updateSession(_ corrected: ReadingSessionRecord) -> Bool {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == corrected.id }) else { return false }
        let previous = sessions[sessionIndex]
        let eventIndex = ReadingSessionEventLink.index(for: previous, in: events)
        sessions[sessionIndex] = corrected
        if let eventIndex {
            events[eventIndex] = ReadingSessionEventLink.event(for: corrected, preservingID: events[eventIndex].id)
        } else {
            events.append(ReadingSessionEventLink.event(for: corrected))
        }
        trimAndPersist()
        return true
    }

    @discardableResult
    func deleteSession(id: UUID) -> Bool {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == id }) else { return false }
        let session = sessions[sessionIndex]
        if let eventIndex = ReadingSessionEventLink.index(for: session, in: events) {
            events.remove(at: eventIndex)
        }
        sessions.remove(at: sessionIndex)
        trimAndPersist()
        return true
    }

    func recordProgress(book: BookProgress, from oldUnits: Int, to newUnits: Int, at date: Date = Date()) {
        guard let bookID = book.bookId, newUnits > oldUnits else { return }
        events.append(ReadingActivityEvent(id: UUID(), bookID: bookID, date: date, kind: .progress,
                                           unitDelta: newUnits - oldUnits, isAudiobook: book.isAudiobook))
        trimAndPersist()
    }

    func recordFinished(book: BookProgress, from oldUnits: Int, at date: Date = Date()) {
        guard let bookID = book.bookId else { return }
        events.append(ReadingActivityEvent(id: UUID(), bookID: bookID, date: date, kind: .finished,
                                           unitDelta: max(0, book.totalUnits - oldUnits), isAudiobook: book.isAudiobook))
        trimAndPersist()
    }

    private func trimAndPersist() {
        if sessions.count > 500 { sessions.removeFirst(sessions.count - 500) }
        if events.count > 2_000 { events.removeFirst(events.count - 2_000) }
        persist()
    }

    private func persist() {
        guard !storageKey.isEmpty else { return }
        let archive = ReadingActivityArchive(deadlines: deadlines, activeSession: activeSession,
                                             sessions: sessions, events: events)
        if let data = try? JSONEncoder().encode(archive) {
            AppGroup.defaults.set(data, forKey: storageKey)
        }
    }

    private static func key(for account: String) -> String {
        let digest = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        return "SoftcoverReadingActivity.v1.\(digest.prefix(24))"
    }
}

@MainActor
private enum ReadingSessionLiveActivity {
    static func startOrUpdate(_ session: ActiveReadingSession) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = contentState(for: session)
        if let activity = ActivityKit.Activity<ReadingSessionActivityAttributes>.activities.first(where: {
            $0.attributes.sessionID == session.id.uuidString
        }) {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }
        for activity in ActivityKit.Activity<ReadingSessionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let attributes = ReadingSessionActivityAttributes(
            sessionID: session.id.uuidString, bookID: session.bookID, title: session.title,
            author: session.author, isAudiobook: session.isAudiobook, totalUnits: session.totalUnits
        )
        _ = try? ActivityKit.Activity.request(attributes: attributes,
                                  content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    }

    static func end(session: ActiveReadingSession? = nil, currentUnits: Int = 0) async {
        for activity in ActivityKit.Activity<ReadingSessionActivityAttributes>.activities where
            session == nil || activity.attributes.sessionID == session?.id.uuidString {
            let state = ReadingSessionActivityAttributes.ContentState(
                accumulatedSeconds: Int(session?.accumulatedSeconds ?? 0), resumedAt: nil,
                isPaused: true, currentUnits: currentUnits
            )
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
        }
    }

    private static func contentState(for session: ActiveReadingSession) -> ReadingSessionActivityAttributes.ContentState {
        ReadingSessionActivityAttributes.ContentState(
            accumulatedSeconds: Int(session.accumulatedSeconds), resumedAt: session.resumedAt,
            isPaused: !session.isRunning, currentUnits: session.startingUnits
        )
    }
}
