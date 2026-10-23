import ActivityKit
import Foundation

struct ReadingSessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var accumulatedSeconds: Int
        var resumedAt: Date?
        var isPaused: Bool
        var currentUnits: Int
    }

    let sessionID: String
    let bookID: Int
    let title: String
    let author: String
    let isAudiobook: Bool
    let totalUnits: Int
}
