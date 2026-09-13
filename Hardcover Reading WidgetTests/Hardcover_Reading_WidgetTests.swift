import Foundation
import Testing
@testable import Softcover

struct SoftcoverModelTests {
    @Test func releaseDatesAreStrictAndCalendarValid() {
        #expect(ReleaseDate.parse("2024-02-29") != nil)
        #expect(ReleaseDate.parse("2026-02-29") == nil)
        #expect(ReleaseDate.parse("2026-2-03") == nil)
        #expect(ReleaseDate.parse("0000-01-01") == nil)
    }

    @Test func audiobookProgressUsesMinutesEvenWhenPagesExist() {
        let book = BookProgress(id: "fixture", title: "Audio", author: "",
                                totalPages: 100, originalTitle: "Audio", isAudiobook: true, totalMinutes: 600, currentMinute: 200)
        let updated = book.withProgress(400)
        #expect(updated.currentMinute == 400)
        #expect(updated.currentPage == 0)
        #expect(updated.totalUnits == 600)
        #expect(book.withProgress(900).currentMinute == 600)
    }

    @Test func ebookFormatTakesPriorityOverStrayDuration() throws {
        let data = Data(#"{"id":1,"pages":216,"audio_seconds":3600,"reading_format":{"format":"Ebook"}}"#.utf8)
        let edition = try JSONDecoder().decode(Edition.self, from: data)
        #expect(!edition.isAudiobook)
        #expect(edition.totalUnits == 216)
    }
}
