import Foundation

struct ReadingDeadline: Codable, Equatable, Sendable {
    let bookID: Int
    var targetDate: Date
    var createdAt: Date

    func unitsPerDay(currentUnits: Int, totalUnits: Int, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        let remaining = max(0, totalUnits - currentUnits)
        guard remaining > 0 else { return 0 }
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: targetDate)
        let distance = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        guard distance >= 0 else { return nil }
        return Int(ceil(Double(remaining) / Double(max(1, distance + 1))))
    }
}

struct ActiveReadingSession: Codable, Equatable, Sendable {
    let id: UUID
    let bookID: Int
    let userBookID: Int?
    let editionID: Int?
    let title: String
    let author: String
    let isAudiobook: Bool
    let totalUnits: Int
    let startingUnits: Int
    var accumulatedSeconds: TimeInterval
    var resumedAt: Date?
    let startedAt: Date

    var isRunning: Bool { resumedAt != nil }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulatedSeconds + max(0, resumedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    mutating func pause(at date: Date = Date()) {
        accumulatedSeconds = elapsed(at: date)
        resumedAt = nil
    }

    mutating func resume(at date: Date = Date()) {
        guard resumedAt == nil else { return }
        resumedAt = date
    }
}

struct ReadingSessionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let bookID: Int
    let title: String
    let isAudiobook: Bool
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let startingUnits: Int
    let endingUnits: Int

    var progressedUnits: Int { max(0, endingUnits - startingUnits) }

    func corrected(startedAt: Date, endedAt: Date, durationSeconds: TimeInterval,
                   startingUnits: Int, endingUnits: Int) -> ReadingSessionRecord? {
        guard endedAt >= startedAt,
              durationSeconds > 0,
              durationSeconds <= endedAt.timeIntervalSince(startedAt) + 1,
              startingUnits >= 0,
              endingUnits >= startingUnits else { return nil }
        return ReadingSessionRecord(
            id: id, bookID: bookID, title: title, isAudiobook: isAudiobook,
            startedAt: startedAt, endedAt: endedAt, durationSeconds: durationSeconds,
            startingUnits: startingUnits, endingUnits: endingUnits
        )
    }
}

struct ReadingActivityEvent: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case progress, session, finished }

    let id: UUID
    let bookID: Int
    let date: Date
    let kind: Kind
    let sessionID: UUID?
    let unitDelta: Int
    let isAudiobook: Bool

    init(id: UUID, bookID: Int, date: Date, kind: Kind, sessionID: UUID? = nil,
         unitDelta: Int, isAudiobook: Bool) {
        self.id = id
        self.bookID = bookID
        self.date = date
        self.kind = kind
        self.sessionID = sessionID
        self.unitDelta = unitDelta
        self.isAudiobook = isAudiobook
    }
}

enum ReadingSessionEventLink {
    static func index(for session: ReadingSessionRecord, in events: [ReadingActivityEvent]) -> Int? {
        if let exact = events.firstIndex(where: { $0.sessionID == session.id }) { return exact }
        return events.indices
            .filter { index in
                let event = events[index]
                return event.sessionID == nil && event.kind == .session && event.bookID == session.bookID
                    && event.isAudiobook == session.isAudiobook && event.unitDelta == session.progressedUnits
            }
            .min { left, right in
                abs(events[left].date.timeIntervalSince(session.endedAt))
                    < abs(events[right].date.timeIntervalSince(session.endedAt))
            }
            .flatMap { abs(events[$0].date.timeIntervalSince(session.endedAt)) <= 1 ? $0 : nil }
    }

    static func event(for session: ReadingSessionRecord, preservingID id: UUID = UUID()) -> ReadingActivityEvent {
        ReadingActivityEvent(
            id: id, bookID: session.bookID, date: session.endedAt, kind: .session,
            sessionID: session.id, unitDelta: session.progressedUnits, isAudiobook: session.isAudiobook
        )
    }
}

struct ReadingActivityMetrics: Equatable, Sendable {
    let currentStreak: Int
    let activeDays: Int
    let sessionCount: Int
    let sessionSeconds: TimeInterval
    let pagesProgressed: Int
    let audioMinutesProgressed: Int

    static func calculate(events: [ReadingActivityEvent], sessions: [ReadingSessionRecord],
                          now: Date = Date(), calendar: Calendar = .current) -> ReadingActivityMetrics {
        let eventDays = Set(events.map { calendar.startOfDay(for: $0.date) })
        let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0.endedAt) })
        let days = eventDays.union(sessionDays)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        var cursor: Date? = days.contains(today) ? today : (days.contains(yesterday) ? yesterday : nil)
        var streak = 0
        while let day = cursor, days.contains(day) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }

        return ReadingActivityMetrics(
            currentStreak: streak,
            activeDays: days.count,
            sessionCount: sessions.count,
            sessionSeconds: sessions.reduce(0) { $0 + max(0, $1.durationSeconds) },
            pagesProgressed: events.filter { !$0.isAudiobook }.reduce(0) { $0 + max(0, $1.unitDelta) },
            audioMinutesProgressed: events.filter(\.isAudiobook).reduce(0) { $0 + max(0, $1.unitDelta) }
        )
    }
}
