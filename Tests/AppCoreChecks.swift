import Foundation

@main
struct AppCoreChecks {
    static var failures: [String] = []
    static var passed = 0

    static func run(_ name: String, _ action: () async throws -> Void) async {
        do {
            try await action()
            passed += 1
            print("PASS \(name)")
        } catch {
            failures.append("\(name): \(error)")
            print("FAIL \(name): \(error)")
        }
    }

    static func main() async throws {
        if CommandLine.arguments.contains("--queries") {
            let queries = [LibraryAPI.identityQuery, LibraryAPI.pageQuery, LibraryAPI.currentBookQuery, LibraryAPI.editionsQuery,
                           BookSearchAPI.query, BookSearchAPI.hydrateQuery, BookSearchAPI.usersQuery, BookSearchAPI.statusQuery,
                           CommunityQueries.upcomingBooks, CommunityQueries.upcomingEditions, CommunityQueries.history,
                           BookDetailQueries.metadata, BookDetailQueries.reviews, BookDetailQueries.reviewLikes, BookDetailQueries.quotes]
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: queries))
            return
        }
        AppGroup.reset()
        defer { AppGroup.reset(); URLProtocol.unregisterClass(AppCoreMockProtocol.self) }

        // Prove shared-session interception before any production API call. If it
        // is unavailable, exit here rather than risking a real network request.
        guard URLProtocol.registerClass(AppCoreMockProtocol.self) else {
            throw AppCoreCheckFailure(description: "Could not install the fail-closed URLProtocol")
        }
        AppCoreMockProtocol.reset { record in
            try require(record.request.url?.host == "softcover-tests.invalid", "Unexpected preflight host")
            return .init(["intercepted": true])
        }
        var preflight = URLRequest(url: URL(string: "https://softcover-tests.invalid/interception")!)
        preflight.timeoutInterval = 2
        _ = try await URLSession.shared.data(for: preflight)
        try require(AppCoreMockProtocol.requests.count == 1, "URLSession.shared is not intercepted; refusing API tests")
        print("All requests intercepted. Defaults suite: \(AppGroup.suiteName)")
        print("UIKit HTML entity decoding and actual HTML parsing are not tested by this executable.")

        await checkDatesAndModels()
        await checkWantToRead()
        await checkHTTP()
        await checkLibrary()
        await checkSnapshots()
        await checkStores()

        print("\n\(passed) groups passed; \(failures.count) failed.")
        if !failures.isEmpty {
            for failure in failures { FileHandle.standardError.write(Data("\(failure)\n".utf8)) }
            exit(1)
        }
    }

    static func checkWantToRead() async {
        let utc = TimeZone(secondsFromGMT: 0)!
        let now = ReleaseDate.parse("2026-09-13")!.addingTimeInterval(43200)
        func book(_ id: Int, _ date: String?) -> BookProgress {
            var book = coreBook(id: id, status: 1)
            book.releaseDate = date
            book.parsedReleaseDate = ReleaseDate.parse(date)
            return book
        }
        let books = [book(9, nil), book(8, "2026-09-12"), book(7, "2027-01-01"), book(6, "2026-09-13"),
                     book(5, "2020-01-01"), book(4, "2026-09-14"), book(3, "2026-09-14"), book(2, "invalid")]
        await run("Want to Read sorts nearest releases before published and unknown dates") {
            func ids(_ sort: WantToReadSort) -> [String] {
                WantToReadPresentation.books(books, query: "", filter: .all, sort: sort, now: now, timeZone: utc).map(\.id)
            }
            try require(ids(.nearestRelease) == ["6", "3", "4", "7", "8", "5", "2", "9"], "Nearest release ordering or stable ties are wrong")
            try require(ids(.newestRelease) == ["7", "3", "4", "6", "8", "5", "2", "9"], "Newest ordering is wrong")
            try require(ids(.oldestRelease) == ["5", "8", "6", "3", "4", "7", "2", "9"], "Oldest ordering is wrong")
            try require(ids(.recentlyAdded) == books.map(\.id), "Recently added changed server order")
        }
        await run("Want to Read filters and search preserve release ordering and date fallback") {
            let upcoming = WantToReadPresentation.books(books, query: "", filter: .upcoming, sort: .nearestRelease, now: now, timeZone: utc)
            let published = WantToReadPresentation.books(books, query: "", filter: .recent, sort: .nearestRelease, now: now, timeZone: utc)
            try require(upcoming.map(\.id) == ["6", "3", "4", "7"], "Today excluded or unknown date included in upcoming")
            try require(published.map(\.id) == ["8", "5"], "Published books are not newest first")
            var fallback = book(10, "2026-09-14")
            fallback.parsedReleaseDate = nil
            fallback.title = "A MATCH in the title"
            var authorMatch = book(11, "2026-09-15")
            authorMatch.author = "Matching Author"
            let matches = WantToReadPresentation.books([authorMatch, fallback] + books, query: "  match \n", filter: .upcoming,
                                                       sort: .nearestRelease, now: now, timeZone: utc)
            try require(matches.map(\.id) == ["10", "11"], "Search lost author, title, whitespace or raw date fallback")
        }
        await run("Release countdown uses local calendar days across midnight, DST and time zones") {
            let cases: [(String, String, String, Int)] = [
                ("2026-09-13T22:30:00Z", "Europe/Stockholm", "2026-09-14", 0),
                ("2026-09-13T22:30:00Z", "America/Los_Angeles", "2026-09-14", 1),
                ("2026-09-14T06:30:00Z", "America/Los_Angeles", "2026-09-14", 1),
                ("2026-09-13T21:59:59Z", "Europe/Stockholm", "2026-09-14", 1),
                ("2026-09-13T22:00:00Z", "Europe/Stockholm", "2026-09-14", 0),
                ("2026-03-28T23:30:00Z", "Europe/Stockholm", "2026-03-30", 1),
                ("2026-10-24T22:30:00Z", "Europe/Stockholm", "2026-10-26", 1),
                ("2024-02-28T12:00:00Z", "Europe/Stockholm", "2024-03-01", 2),
                ("2026-12-31T12:00:00Z", "Europe/Stockholm", "2027-01-01", 1),
                ("2026-09-15T12:00:00Z", "Europe/Stockholm", "2026-09-14", -1)
            ]
            for (instant, zone, release, expected) in cases {
                let now = ISO8601DateFormatter().date(from: instant)!
                let days = WantToReadPresentation.daysUntil(ReleaseDate.parse(release)!, now: now, timeZone: TimeZone(identifier: zone)!)
                try require(days == expected, "Wrong day count for \(instant) in \(zone): \(days)")
            }
            let release = book(12, "2026-09-14")
            let localMidnight = ISO8601DateFormatter().date(from: "2026-09-14T22:00:00Z")!
            let remaining = WantToReadPresentation.books([release], query: "", filter: .upcoming, sort: .nearestRelease,
                                                        now: localMidnight, timeZone: TimeZone(identifier: "Europe/Stockholm")!)
            try require(remaining.isEmpty, "Published book remained in upcoming after local midnight")
        }
    }

    static func checkDatesAndModels() async {
        await run("Quote page uses canonical metadata position and rejects malformed journals") {
            func response(_ journals: [[String: Any]]) throws -> Data {
                try JSONSerialization.data(withJSONObject: ["data": ["user_books": [
                    ["book": ["title": "Fixture"], "reading_journals": journals]
                ]]])
            }
            let parsed = try Quote.decodeBookResponse(response([
                ["id": 1, "entry": "Text", "metadata": ["position": ["value": 42, "unit": "page"]]],
                ["id": 2, "entry": "Text", "metadata": ["page": 8]]
            ]), bookID: 7)
            try require(parsed.map(\.page) == [42, 8], "Quote page information was lost")
            let empty = try Quote.decodeBookResponse(response([]), bookID: 7)
            try require(empty.isEmpty, "Valid empty quotes rejected")
            do {
                _ = try Quote.decodeBookResponse(response([["id": 1]]), bookID: 7)
                throw AppCoreCheckFailure(description: "Malformed quote accepted as empty")
            } catch is HardcoverNetworkError { }
        }
        await run("ReleaseDate valid leap dates and round trip") {
            for date in ["2024-02-29", "2000-02-29", "2026-09-13", "2026-12-31", "2026-01-01"] {
                guard let parsed = ReleaseDate.parse(date) else { throw AppCoreCheckFailure(description: "Rejected \(date)") }
                try require(ReleaseDate.string(parsed) == date, "Round trip changed \(date)")
            }
        }
        await run("ReleaseDate rejects impossible or malformed dates") {
            let invalid: [String?] = [nil, "", "garbage", "2023-02-29", "1900-02-29", "2024-02-30",
                                     "2026-04-31", "2026-00-10", "2026-13-10", "2026-01-00",
                                     "2026-01-32", "2026-9-13", "2026-09-3", "2026-09-13 ",
                                     "2026-09-13T12:00:00Z"]
            for date in invalid { try require(ReleaseDate.parse(date) == nil, "Accepted \(date ?? "nil")") }
        }
        await run("ReleaseDate year bounds") {
            for date in ["0000-01-01", "-001-01-01", "10000-01-01"] {
                try require(ReleaseDate.parse(date) == nil, "Accepted out-of-bounds year \(date)")
            }
        }
        await run("Upcoming month/quarter/year/recent intervals and leap boundaries") {
            let now = ReleaseDate.parse("2026-09-13")!.addingTimeInterval(3600 * 23)
            let expected = [("recent", "2026-08-14", "2026-09-14"), ("month", "2026-09-13", "2026-10-13"),
                            ("quarter", "2026-09-13", "2026-12-13"), ("year", "2026-09-13", "2027-09-13")]
            for (filter, start, end) in expected {
                let range = CommunityQueries.upcomingInterval(filter: filter, now: now)
                try require(range.start == start && range.endExclusive == end, "Incorrect \(filter) bounds")
            }
            let january = CommunityQueries.upcomingInterval(filter: "month", now: ReleaseDate.parse("2024-01-31")!)
            let leap = CommunityQueries.upcomingInterval(filter: "year", now: ReleaseDate.parse("2024-02-29")!)
            try require(january.endExclusive == "2024-02-29" && leap.endExclusive == "2025-02-28", "Calendar month/year overflow not clamped")
        }
        await run("Library rating, release date, edition and format mapping") {
            let row = try decodeRow(libraryRow(id: 7))
            guard let book = LibraryAPI.makeBook(row) else { throw AppCoreCheckFailure(description: "Valid row discarded") }
            try require(book.id == "7" && book.bookId == 1007 && book.editionId == 2007 && book.statusId == 2, "Wrong identifiers")
            try require(book.title == "Edition 7" && book.originalTitle == "Original 7" && book.author == "Test Author", "Wrong title/author mapping")
            try require(book.editionAverageRating == 4.25 && book.userRating == 3.5, "Personal and average ratings mixed up")
            try require(book.coverImageUrl == "https://images.invalid/edition.jpg", "Edition cover not preferred")
            try require(book.releaseDate == "2026-09-01" && book.parsedReleaseDate == ReleaseDate.parse("2026-09-01"), "Wrong release mapping")
            try require(!book.isAudiobook && book.readingFormat == "Ebook" && book.currentPage == 80, "Duration overrode explicit ebook format")
            try require(book.displayFormat == NSLocalizedString("E-book", comment: ""), "Ebook format label was not normalized")
            try require(abs(book.progress - 1.0 / 3.0) < 0.0001, "Ebook used audio progress")
            let physical = LibraryAPI.makeBook(try decodeRow(libraryRow(id: 17, format: "Read")))!
            try require(physical.displayFormat == NSLocalizedString("Physical book", comment: ""), "Hardcover Read label leaked into the library")
            let listened = LibraryAPI.makeBook(try decodeRow(libraryRow(id: 18, format: "Listened")))!
            try require(listened.isAudiobook && listened.displayFormat == NSLocalizedString("Audiobook", comment: ""), "Hardcover Listened label was not mapped as audio")
            var fallback = libraryRow(id: 8)
            fallback["edition"] = NSNull()
            let mapped = LibraryAPI.makeBook(try decodeRow(fallback))
            try require(mapped?.title == "Original 8" && mapped?.releaseDate == "2024-02-29", "Missing edition lost book fallback")
            try require(mapped?.coverImageUrl == "https://images.invalid/book.jpg", "Missing edition lost book cover")
        }
        await run("Library audio with page metadata uses time") {
            let book = LibraryAPI.makeBook(try decodeRow(libraryRow(id: 9, format: "Audio")))!
            try require(book.isAudiobook && book.totalPages == 240, "Audio fixture lost independent page metadata")
            try require(book.currentPage == 0 && book.currentMinute == 20 && book.totalMinutes == 60, "Audio units not seconds-to-minutes")
            try require(abs(book.progress - 1.0 / 3.0) < 0.0001, "Audio progress used page count")
        }
        await run("Edition language/year metadata and format-specific length") {
            var source: [String: Any] = ["id": 20, "title": "Edition fixture", "pages": 216, "audio_seconds": 3600,
                                          "release_date": "2026-09-01", "reading_format": ["format": "Ebook"],
                                          "publisher": ["name": "Fixture Publisher"],
                                          "language": ["code2": "en", "language": "English"]]
            let ebook = try JSONDecoder().decode(Edition.self, from: JSONSerialization.data(withJSONObject: source))
            let language = Locale.current.localizedString(forLanguageCode: "en")!.localizedCapitalized
            let pages = String(format: NSLocalizedString("%d pages", comment: ""), 216)
            try require(ebook.language?.code2 == "en" && ebook.displayInfo.contains(language), "Edition language not decoded/displayed")
            try require(ebook.displayInfo.contains("2026") && ebook.displayInfo.contains("Fixture Publisher"), "Release year or publisher lost")
            try require(ebook.displayInfo.contains(pages) && !ebook.displayInfo.contains("1h"), "Ebook length presented as audio")
            source["reading_format"] = ["format": "Audio"]
            source["language"] = ["language": "Fixture Language"]
            let audio = try JSONDecoder().decode(Edition.self, from: JSONSerialization.data(withJSONObject: source))
            try require(audio.isAudiobook && audio.displayInfo.contains("1h 0m") && !audio.displayInfo.contains(pages), "Audio length presented as pages")
            try require(audio.displayInfo.contains("Fixture Language"), "Language-name fallback lost")
            source["reading_format"] = ["format": "Read"]
            let physical = try JSONDecoder().decode(Edition.self, from: JSONSerialization.data(withJSONObject: source))
            try require(!physical.isAudiobook && physical.displayFormat == NSLocalizedString("Physical book", comment: ""), "Edition Read label was not normalized")
            source["language"] = NSNull()
            source["release_date"] = "2026-02-30"
            let missing = try JSONDecoder().decode(Edition.self, from: JSONSerialization.data(withJSONObject: source))
            try require(missing.language == nil && !missing.displayInfo.contains("2026"), "Invalid release date leaked into edition metadata")
        }
        await run("Library mapped progress clamps invalid server values") {
            for audio in [false, true] {
                let format = audio ? "Audio" : "Ebook"
                let negative = LibraryAPI.makeBook(try decodeRow(libraryRow(id: 10, format: format, progressPages: -12, progressSeconds: -120)))!
                let excessive = LibraryAPI.makeBook(try decodeRow(libraryRow(id: 11, format: format, progressPages: 900, progressSeconds: 99000)))!
                try require(negative.progress == 0 && negative.currentUnits == 0, "Negative current units survived API mapping (\(format))")
                try require(excessive.progress == 1 && excessive.currentUnits == excessive.totalUnits, "Current units exceed total after API mapping (\(format))")
            }
        }
        await run("BookProgress clamps page and audio edits independently") {
            for audio in [false, true] {
                let original = coreBook(audio: audio)
                let negative = original.withProgress(-500)
                let excessive = original.withProgress(Int.max)
                let middle = original.withProgress(30)
                try require(negative.currentUnits == 0 && negative.progress == 0, "Negative progress not clamped")
                try require(excessive.currentUnits == original.totalUnits && excessive.progress == 1, "Progress exceeds book length")
                try require(middle.currentUnits == 30, "Wrong progress units")
                try require(audio ? middle.currentPage == original.currentPage : middle.currentMinute == original.currentMinute, "Changed other format's metadata")
                var unknown = original
                unknown.totalMinutes = 0; unknown.totalPages = 0
                let unknownUpdate = unknown.withProgress(10)
                try require(unknownUpdate.currentUnits == 10 && unknownUpdate.progress == 0, "Unknown total creates NaN or discards entered progress")
            }
        }
        await run("BookProgress snapshot Codable round trip") {
            var book = coreBook(audio: true)
            book.parsedReleaseDate = ReleaseDate.parse("2024-02-29")
            let decoded = try JSONDecoder().decode(BookProgress.self, from: JSONEncoder().encode(book))
            try require(decoded == book, "BookProgress lost cached fields")
        }
        await run("ReadingGoal coercion and percent scales") {
            let fixtures: [(String, Double)] = [
                (#"{"id":"1","goal":"20","metric":"book","start_date":"2026-01-01","end_date":"2026-12-31","progress":"5","calculatedProgress":"25"}"#, 0.25),
                (#"{"id":1,"goal":20,"metric":"book","startDate":"2026-01-01","endDate":"2026-12-31","progress":5,"percentComplete":0.25}"#, 0.25),
                (#"{"id":1,"goal":20,"metric":"book","startDate":"2026-01-01","endDate":"2026-12-31","progress":30}"#, 1)
            ]
            for (json, percent) in fixtures {
                let goal = try JSONDecoder().decode(ReadingGoal.self, from: Data(json.utf8))
                try require(goal.percentComplete == percent && goal.id == 1, "Goal decoding regressed")
            }
        }
    }

    static func checkHTTP() async {
        await run("HTTP status 401/403/429/500 remain distinct; no automatic retry") {
            for status in [401, 403, 429, 500] {
                let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
                AppCoreMockProtocol.reset { _ in .init([:], status: status, headers: ["Retry-After": "45"]) }
                try await requireError("HTTP \(status)", matching: { error in
                    switch (status, error) {
                    case (401, HardcoverNetworkError.signIn), (403, HardcoverNetworkError.permission), (500, HardcoverNetworkError.server(500)): return true
                    case (429, HardcoverNetworkError.rateLimited(let date)): return date.timeIntervalSinceNow > 40
                    default: return false
                    }
                }) { _ = try await http.data(for: coreRequest()) }
                try require(AppCoreMockProtocol.requests.count == 1, "HTTP \(status) was replayed")
            }
        }
        await run("Malformed/missing data and partial GraphQL errors cannot enter cache") {
            let replies: [AppCoreMockProtocol.Reply] = [
                .init(raw: "not-json"), .init([:]), .init(["data": NSNull()]),
                .init(["errors": [["message": "Denied"]]]),
                .init(["data": ["me": []], "errors": [["message": "Partial read failed"]]])
            ]
            for bad in replies {
                let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
                let request = try coreRequest()
                AppCoreMockProtocol.reset { _ in
                    AppCoreMockProtocol.requests.count == 1 ? bad : .init(["data": ["me": []]])
                }
                try await requireError("Invalid GraphQL response") { _ = try await http.data(for: request) }
                _ = try await http.data(for: request)
                _ = try await http.data(for: request)
                try require(AppCoreMockProtocol.requests.count == 2, "Failed response was cached or successful response not cached")
            }
        }
        await run("Successful empty arrays are valid cached reads") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let request = try coreRequest()
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]]) }
            let first = try await http.data(for: request).0
            let cached = try await http.data(for: request).0
            try require(first == cached && AppCoreMockProtocol.requests.count == 1, "Empty successful read not cached")
            await http.invalidate()
            _ = try await http.data(for: request)
            try require(AppCoreMockProtocol.requests.count == 2, "Invalidation did not evict cache")
        }
        await run("Concurrent identical reads coalesce") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let request = try coreRequest()
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]], delay: 0.1) }
            let outputs = try await withThrowingTaskGroup(of: Data.self) { group in
                for _ in 0..<12 { group.addTask { try await http.data(for: request).0 } }
                var output: [Data] = []
                for try await data in group { output.append(data) }
                return output
            }
            try require(outputs.count == 12 && Set(outputs).count == 1, "Coalesced callers got inconsistent data")
            try require(AppCoreMockProtocol.requests.count == 1, "Identical concurrent reads were duplicated")
        }
        await run("Transport cache is isolated by account and query variables") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let a = try coreRequest(account: "cache-a")
            let b = try coreRequest(account: "cache-b")
            var c = a
            c.httpBody = try JSONSerialization.data(withJSONObject: ["query": "query Probe { me { id username } }", "variables": ["offset": 50]])
            AppCoreMockProtocol.reset { record in .init(["data": ["account": record.request.value(forHTTPHeaderField: "Authorization") ?? "", "query": record.query]]) }
            let firstA = try await http.data(for: a).0
            let firstB = try await http.data(for: b).0
            _ = try await http.data(for: c)
            let cachedA = try await http.data(for: a).0
            try require(firstA != firstB && firstA == cachedA && AppCoreMockProtocol.requests.count == 3, "Cross-account or cross-query cache leak")
        }
        await run("Cancelled coalesced waiter cannot cancel another reader or commit data") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let request = try coreRequest()
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]], delay: 0.15) }
            let first = Task { try await http.data(for: request).0 }
            try await eventually("Request did not start") { AppCoreMockProtocol.requests.count == 1 }
            let second = Task { try await http.data(for: request).0 }
            try await eventuallyAsync("Both readers did not join the shared request") { await http.pendingReaderCount == 2 }
            first.cancel()
            try await requireError("Cancelled waiter", matching: { $0 is CancellationError }) { _ = try await first.value }
            _ = try await second.value
            try require(AppCoreMockProtocol.requests.count == 1, "Cancelled waiter broke coalescing")
        }
        await run("Cancelled request fanout still shares one transport for surviving readers") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let request = try coreRequest()
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]], delay: 0.12) }
            let tasks = (0..<16).map { _ in Task { try await http.data(for: request).0 } }
            try await eventuallyAsync("All fanout readers did not join") { await http.pendingReaderCount == 16 }
            for index in stride(from: 0, to: tasks.count, by: 2) { tasks[index].cancel() }
            for (index, task) in tasks.enumerated() {
                if index.isMultiple(of: 2) {
                    try await requireError("Cancelled fanout caller", matching: { $0 is CancellationError }) { _ = try await task.value }
                } else { _ = try await task.value }
            }
            try require(AppCoreMockProtocol.requests.count == 1, "Cancelled fanout produced duplicate transport requests")
        }
        await run("All cancelled coalesced callers cannot cache their abandoned response") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let request = try coreRequest()
            AppCoreMockProtocol.reset { _ in .init(["data": ["generation": AppCoreMockProtocol.requests.count]], delay: 0.1) }
            let tasks = (0..<8).map { _ in Task { try await http.data(for: request).0 } }
            try await eventuallyAsync("All abandoned readers did not join") { await http.pendingReaderCount == 8 }
            tasks.forEach { $0.cancel() }
            for task in tasks {
                try await requireError("Abandoned caller", matching: { $0 is CancellationError }) { _ = try await task.value }
            }
            _ = try await http.data(for: request)
            try require(AppCoreMockProtocol.requests.count == 2, "Abandoned response entered cache")
        }
        await run("Cancelled queued read fanout must not spend network quota") {
            let scheduler = HardcoverRequestScheduler()
            let account = "cancelled-queue-\(UUID().uuidString)"
            try await scheduler.acquire(authorization: "Bearer test-only-\(account)", cost: 5)
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: scheduler)
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]]) }
            let tasks = (0..<2).map { index in
                Task { try await http.data(for: coreRequest("query Cancelled\(index) { me { id username } }", account: account)).0 }
            }
            // Wait for actual registered readers, not a timing assumption.
            try await eventuallyAsync("Queued readers did not register") { await http.pendingReaderCount == 2 }
            try require(AppCoreMockProtocol.requests.isEmpty, "Fixture failed to hold requests in scheduler")
            tasks.forEach { $0.cancel() }
            for task in tasks {
                try await requireError("Cancelled queued reader", matching: { $0 is CancellationError }) { _ = try await task.value }
            }
            try require(AppCoreMockProtocol.requests.isEmpty, "Cancelled queued reads still consumed API calls")
        }
        await run("Cancelled fresh read must not leave scheduler work behind") {
            let scheduler = HardcoverRequestScheduler()
            let account = "cancelled-fresh-\(UUID().uuidString)"
            try await scheduler.acquire(authorization: "Bearer test-only-\(account)", cost: 5)
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: scheduler)
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]]) }
            let task = Task { try await http.data(for: coreRequest(account: account), cacheTTL: 0).0 }
            try await eventuallyAsync("Fresh reader did not register") { await http.pendingReaderCount == 1 }
            try require(AppCoreMockProtocol.requests.isEmpty, "Fresh fixture failed to hold request in scheduler")
            task.cancel()
            try await requireError("Cancelled fresh read", matching: { $0 is CancellationError }) { _ = try await task.value }
            try require(AppCoreMockProtocol.requests.isEmpty, "Cancelled fresh read still consumed an API call")
        }
        await run("Invalidation rejects older in-flight response without evicting replacement") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let request = try coreRequest()
            AppCoreMockProtocol.reset { _ in
                let first = AppCoreMockProtocol.requests.count == 1
                return .init(["data": ["generation": first ? 1 : 2]], delay: first ? 0.3 : 0.01)
            }
            let old = Task { try await http.data(for: request).0 }
            try await eventually("Old request did not start") { AppCoreMockProtocol.requests.count == 1 }
            await http.invalidate()
            let replacement = try await http.data(for: request).0
            try await requireError("Invalidated request") { _ = try await old.value }
            let cached = try await http.data(for: request).0
            try require(replacement == cached && AppCoreMockProtocol.requests.count == 2, "Old response replaced or evicted fresh cache")
        }
        await run("Fresh reads bypass cache") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let request = try coreRequest()
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]]) }
            _ = try await http.data(for: request)
            _ = try await http.data(for: request, cacheTTL: 0)
            try require(AppCoreMockProtocol.requests.count == 2, "Fresh read reused cache")
        }
        await run("Mutations are never retried, cached or coalesced") {
            for status in [200, 429, 500] {
                let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
                let request = try coreRequest("mutation Save { update_user_books { affected_rows } }")
                AppCoreMockProtocol.reset { _ in .init(["data": ["update_user_books": ["affected_rows": 1]]], status: status, headers: ["Retry-After": "60"], delay: 0.01) }
                if status == 200 {
                    async let first = http.data(for: request)
                    async let second = http.data(for: request)
                    _ = try await (first, second)
                    try require(AppCoreMockProtocol.requests.count == 2, "Mutations were coalesced")
                    _ = try await http.data(for: request)
                    try require(AppCoreMockProtocol.requests.count == 3, "Mutation was cached")
                } else {
                    try await requireError("Failed mutation") { _ = try await http.data(for: request) }
                    try require(AppCoreMockProtocol.requests.count == 1, "Failed mutation was replayed")
                }
            }
        }
        await run("Successful mutation invalidates only its account's read cache") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let a = try coreRequest(account: "mutation-a")
            let b = try coreRequest(account: "mutation-b")
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]]) }
            _ = try await http.data(for: a)
            _ = try await http.data(for: b)
            _ = try await http.data(for: coreRequest("mutation Save { save }", account: "mutation-a"))
            _ = try await http.data(for: b)
            _ = try await http.data(for: a)
            try require(AppCoreMockProtocol.requests.count == 4, "Mutation invalidated wrong account or failed to invalidate its own cache")
        }
        await run("Pre-mutation read cannot repopulate invalidated account cache") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let read = try coreRequest(account: "mutation-race")
            let other = try coreRequest(account: "mutation-race-other")
            AppCoreMockProtocol.reset { record in
                if record.query.hasPrefix("mutation") { return .init(["data": ["save": true]]) }
                let initial = AppCoreMockProtocol.requests.count == 2
                return .init(["data": ["generation": initial ? 1 : 2]], delay: initial ? 0.15 : 0)
            }
            _ = try await http.data(for: other)
            let old = Task { try await http.data(for: read).0 }
            try await eventually("Pre-mutation request not sent") { AppCoreMockProtocol.requests.count == 2 }
            _ = try await http.data(for: coreRequest("mutation Save { save }", account: "mutation-race"))
            _ = try? await old.value
            let fresh = try await http.data(for: read).0
            let root = try JSONSerialization.jsonObject(with: fresh) as! [String: Any]
            try require((root["data"] as? [String: Any])?["generation"] as? Int == 2, "Old read repopulated cache after mutation")
            _ = try await http.data(for: other)
            try require(AppCoreMockProtocol.requests.count == 4, "Pre-mutation read was cached or unrelated account cache was invalidated")
        }
        await run("Cancelled mutation with server success invalidates reads without replay") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            let account = "cancelled-mutation"
            let read = try coreRequest(account: account)
            AppCoreMockProtocol.reset { record in
                if record.query.hasPrefix("mutation") { return .init(["data": ["save": true]], delay: 0.1) }
                return .init(["data": ["me": []]])
            }
            _ = try await http.data(for: read)
            let mutation = Task { try await http.data(for: coreRequest("mutation Save { save }", account: account)).0 }
            try await eventually("Mutation not sent") { AppCoreMockProtocol.requests.count == 2 }
            mutation.cancel()
            _ = try? await mutation.value
            // A sent mutation must finish without replay, even if its observer
            // leaves the screen. Its successful acknowledgement invalidates reads.
            try await Task.sleep(for: .milliseconds(150))
            _ = try await http.data(for: read)
            try require(AppCoreMockProtocol.requests.filter { $0.query.hasPrefix("mutation") }.count == 1, "Cancelled mutation was replayed")
            try require(AppCoreMockProtocol.requests.count == 3, "Acknowledged mutation left stale read cache after caller cancellation")
        }
        await run("Rate limiting blocks one account without blocking another") {
            let scheduler = HardcoverRequestScheduler()
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: scheduler)
            let limited = try coreRequest(account: "limited")
            AppCoreMockProtocol.reset { record in
                record.request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-limited"
                    ? .init([:], status: 429, headers: ["Retry-After": "120"])
                    : .init(["data": ["me": []]])
            }
            try await requireError("First limited request") { _ = try await http.data(for: limited) }
            try await requireError("Retry after long rate limit", matching: { if case HardcoverNetworkError.rateLimited = $0 { return true }; return false }) {
                _ = try await http.data(for: limited)
            }
            _ = try await http.data(for: coreRequest(account: "unlimited"))
            try require(AppCoreMockProtocol.requests.count == 2, "Scheduler retried limited account or blocked unrelated account")
            let response = HTTPURLResponse(url: limited.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "Wed, 01 Jan 2031 00:00:00 GMT"])!
            try require(ReleaseDate.string(HardcoverRequestScheduler.retryDate(response)) == "2031-01-01", "HTTP-date Retry-After not parsed")
        }
        await run("Legacy checked read does not turn swallowed transport errors into empty success") {
            let http = HardcoverHTTP(session: AppCoreMockProtocol.session(), scheduler: HardcoverRequestScheduler())
            AppCoreMockProtocol.reset { _ in .init([:], status: 500) }
            try await requireError("Swallowed error must propagate", matching: { if case HardcoverNetworkError.server(500) = $0 { return true }; return false }) {
                let _: [Int] = try await HardcoverReadScope.checked {
                    _ = try? await http.data(for: coreRequest())
                    return []
                }
            }
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": []]]) }
            let empty: [Int] = try await HardcoverReadScope.checked {
                _ = try? await http.data(for: coreRequest())
                return []
            }
            try require(empty.isEmpty, "Genuine empty result treated as an error")
        }
    }

    static func checkLibrary() async {
        await run("Library rejects invalid pagination before transport") {
            AppGroup.useAccount()
            AppCoreMockProtocol.reset { _ in throw AppCoreCheckFailure(description: "Invalid pagination hit transport") }
            for (offset, limit) in [(-1, 50), (0, 0), (0, -1), (0, 101), (0, Int.max)] {
                try await requireError("Invalid offset/limit") { _ = try await LibraryAPI.page(status: 2, offset: offset, limit: limit) }
            }
            try require(AppCoreMockProtocol.requests.isEmpty, "Invalid page sent a request")
        }
        await run("Library pagination returns all 125 books with correct offsets and ordering") {
            AppGroup.useAccount()
            AppGroup.defaults.removeObject(forKey: "CurrentlyReadingSortOrder")
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 42, "username": "fixture"]]]]) }
                try require(record.query == LibraryAPI.pageQuery, "Unexpected library query")
                try require(record.variables["userID"] as? Int == 42 && record.variables["status"] as? Int == 2, "Identity/status not forwarded")
                let offset = record.variables["offset"] as? Int ?? -1
                let limit = record.variables["limit"] as? Int ?? 0
                let order = record.variables["order"] as? [[String: String]]
                try require(order == [["updated_at": "desc"], ["id": "desc"]], "Unstable reading order")
                try require(offset >= 0 && limit == 51, "Pagination does not request one lookahead row")
                let rows = offset < 125 ? (offset..<min(125, offset + limit)).map { libraryRow(id: $0 + 1) } : []
                return .init(["data": ["user_books": rows]])
            }
            var books: [BookProgress] = []
            var offset = 0
            var offsets: [Int] = []
            for _ in 0..<4 {
                let page = try await LibraryAPI.page(status: 2, offset: offset)
                books += page.books; offset = page.nextOffset; offsets.append(offset)
                if !page.hasMore { break }
            }
            try require(books.count == 125 && Set(books.map(\.id)).count == 125, "Pagination lost or duplicated books beyond 100")
            try require(offsets == [50, 100, 125], "Wrong cursor offsets: \(offsets)")
            try require(AppCoreMockProtocol.requests.count == 4, "Identity repeated or per-book requests detected")
        }
        await run("Library successful empty page and absent own book") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 1, "username": "fixture"]]]]) }
                return .init(["data": ["user_books": []]])
            }
            let empty = try await LibraryAPI.page(status: 1, offset: 100)
            try require(empty.books.isEmpty && !empty.hasMore && empty.nextOffset == 100, "Empty page has more or advances cursor")
            let missing = try await LibraryAPI.ownBook(bookID: 1234)
            try require(missing == nil, "Absent own book fabricated a row")
        }
        await run("Library missing/partial rows cannot overwrite last-good snapshot") {
            for bad in [["data": ["unexpected": []]], ["data": ["user_books": []], "errors": [["message": "Partial permission error"]]]] as [[String: Any]] {
                AppGroup.useAccount()
                await HardcoverHTTP.shared.invalidate()
                LibrarySnapshot.save([coreBook()], status: 2, complete: true)
                AppCoreMockProtocol.reset { record in
                    if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 1, "username": "fixture"]]]]) }
                    return .init(bad)
                }
                try await requireError("Failed read must not become empty success") {
                    let page = try await LibraryAPI.page(status: 2)
                    LibrarySnapshot.save(page.books, status: 2, complete: !page.hasMore)
                }
                try require(LibrarySnapshot.load(status: 2)?.books.count == 1, "Failed read destroyed offline snapshot")
            }
        }
        await run("Library rejects response from a changed account") {
            AppGroup.useAccount("switch-old")
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { _ in .init(["data": ["me": [["id": 1, "username": "old"]]]], delay: 0.1) }
            let old = Task { try await LibraryAPI.identity() }
            try await eventually("Account request did not start") { AppCoreMockProtocol.requests.count == 1 }
            AppGroup.useAccount("switch-new")
            try await requireError("Account changed during read", matching: { if case HardcoverNetworkError.accountChanged = $0 { return true }; return false }) {
                _ = try await old.value
            }
        }
        await run("Library sign-out fails before transport") {
            AppGroup.defaults.removeObject(forKey: "HardcoverAPIKey")
            AppCoreMockProtocol.reset { _ in throw AppCoreCheckFailure(description: "Signed-out request hit transport") }
            try await requireError("Signed-out request", matching: { if case HardcoverNetworkError.signIn = $0 { return true }; return false }) {
                _ = try await LibraryAPI.identity()
            }
            try require(AppCoreMockProtocol.requests.isEmpty, "Signed-out request sent")
        }
    }

    static func checkSnapshots() async {
        await run("Library snapshots strip image bytes, isolate accounts and statuses") {
            AppGroup.useAccount("snapshot-a")
            LibrarySnapshot.clear()
            LibrarySnapshot.save([coreBook(id: 1)], status: 2, complete: false)
            LibrarySnapshot.save([coreBook(id: 2, status: 1)], status: 1, complete: true)
            try require(LibrarySnapshot.load(status: 2)?.books.first?.coverImageData == nil, "Snapshot stores heavy cover bytes")
            try require(LibrarySnapshot.load(status: 2)?.complete == false, "Partial snapshot marked complete")
            AppGroup.useAccount("snapshot-b")
            try require(LibrarySnapshot.load(status: 2) == nil, "Account B read account A's library")
            LibrarySnapshot.save([coreBook(id: 3)], status: 2, complete: true)
            AppGroup.useAccount("snapshot-a")
            try require(LibrarySnapshot.load(status: 2)?.books.map(\.id) == ["1"], "Account B overwrote account A")
            try require(LibrarySnapshot.load(status: 1)?.books.map(\.id) == ["2"], "Status snapshots mixed")
            try require(LibrarySnapshot.load(status: 2, maxAge: -1) == nil, "Expired snapshot treated as fresh")
            AppGroup.defaults.removeObject(forKey: "HardcoverAPIKey")
            try require(LibrarySnapshot.load(status: 2) == nil, "Signed-out user read snapshot")
        }
        await run("Snapshot invalidation preserves last-good data and original age") {
            AppGroup.useAccount()
            LibrarySnapshot.save([coreBook()], status: 2, complete: true)
            LibrarySnapshot.save([coreBook(status: 1)], status: 1, complete: true)
            let original = LibrarySnapshot.load(status: 2)!
            LibrarySnapshot.invalidate(status: 2)
            let stale = LibrarySnapshot.load(status: 2)!
            try require(stale.stale && stale.books == original.books && stale.date == original.date, "Invalidation discarded or rejuvenated data")
            try require(LibrarySnapshot.load(status: 1)?.stale == false, "Invalidation staled an unrelated list")
            LibrarySnapshot.update(book: coreBook().withProgress(100))
            let changed = LibrarySnapshot.load(status: 2)!
            try require(changed.books.first?.currentPage == 100 && changed.date == original.date && changed.stale, "Book update rejuvenated or unstaled list")
            try require(changed.books.first?.coverImageData == nil, "Book update restored heavy image data")
            LibrarySnapshot.update(book: coreBook(id: 99))
            try require(LibrarySnapshot.load(status: 2)?.books.count == 1, "Update inserted absent book into incomplete list")
        }
        await run("Snapshot status update removes stale membership without fabricating destination order") {
            AppGroup.useAccount()
            LibrarySnapshot.save([coreBook()], status: 2, complete: true)
            LibrarySnapshot.update(book: coreBook(status: 3))
            try require(LibrarySnapshot.load(status: 2)?.books.isEmpty == true, "Finished book remains in currently reading snapshot")
            try require(LibrarySnapshot.load(status: 3) == nil, "Update fabricated a complete destination snapshot")
        }
    }

    @MainActor
    static func checkStores() async {
        await run("Search older response cannot replace newer query") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == BookSearchAPI.query {
                    let old = record.variables["query"] as? String == "old"
                    return .init(["data": ["search": ["ids": [old ? 1 : 2], "results": [["id": old ? 1 : 2, "title": old ? "Old" : "New", "author_names": []]]]]], delay: old ? 0.2 : 0.01)
                }
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 42, "username": "fixture"]]]]) }
                if record.query == BookSearchAPI.statusQuery { return .init(["data": ["user_books": []]]) }
                throw AppCoreCheckFailure(description: "Unexpected search query")
            }
            let store = BookSearchStore()
            let auth = HardcoverConfig.authorizationHeaderValue
            let first = Task { await store.search(.init(text: "old", type: "Book", account: auth), debounce: false) }
            try await eventually("First search not sent") { AppCoreMockProtocol.requests.count == 1 }
            await store.search(.init(text: "new", type: "Book", account: auth), debounce: false)
            await first.value
            try require(store.books.map(\.title) == ["New"] && store.completed && !store.isLoading, "Old search overwrote new results")
            try require(store.error == nil, "Successful search displayed an error")
        }
        await run("Clearing query prevents in-flight results from returning") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { _ in
                .init(["data": ["search": ["ids": [1], "results": [["id": 1, "title": "Old", "author_names": []]]]]], delay: 0.12)
            }
            let store = BookSearchStore()
            let auth = HardcoverConfig.authorizationHeaderValue
            let old = Task { await store.search(.init(text: "old", type: "Book", account: auth), debounce: false) }
            try await eventually("Search not sent") { AppCoreMockProtocol.requests.count == 1 }
            await store.search(.init(text: "", type: "Book", account: auth), debounce: false)
            await old.value
            try require(store.books.isEmpty && store.users.isEmpty && !store.completed && !store.isLoading, "Cleared search resurrected old data")
            try require(AppCoreMockProtocol.requests.count == 1, "Clear query sent a request or loaded old statuses")
        }
        await run("Cancelled debounce sends no request") {
            AppGroup.useAccount()
            AppCoreMockProtocol.reset { _ in throw AppCoreCheckFailure(description: "Cancelled debounce hit transport") }
            let store = BookSearchStore()
            let auth = HardcoverConfig.authorizationHeaderValue
            let task = Task { await store.search(.init(text: "cancel", type: "Book", account: auth)) }
            task.cancel()
            await task.value
            try require(AppCoreMockProtocol.requests.isEmpty && !store.isLoading && store.error == nil, "Cancelled debounce caused API call/error")
        }
        await run("Search failure remains distinct from successful empty search") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.variables["query"] as? String == "broken" { return .init([:], status: 500) }
                return .init(["data": ["search": ["ids": [], "results": []]]])
            }
            let store = BookSearchStore()
            let auth = HardcoverConfig.authorizationHeaderValue
            await store.search(.init(text: "broken", type: "Book", account: auth), debounce: false)
            try require(store.error != nil && !store.completed && !store.isLoading, "Failed search shown as empty success")
            await store.search(.init(text: "empty", type: "Book", account: auth), debounce: false)
            try require(store.error == nil && store.completed && store.books.isEmpty && !store.hasMore, "Empty success shown as failure")
        }
        await run("Search IDs-only hydration preserves rank and pagination") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == BookSearchAPI.query { return .init(["data": ["search": ["ids": Array(1...25).map(String.init)]]]) }
                if record.query == BookSearchAPI.hydrateQuery {
                    return .init(["data": ["books": (1...25).reversed().map { ["id": $0, "title": "Book \($0)"] }]])
                }
                throw AppCoreCheckFailure(description: "Unexpected hydration query")
            }
            let result = try await BookSearchAPI.search(text: "author: test", type: "Book", page: 1)
            try require(result.books.compactMap(\.bookId) == Array(1...25) && result.hasMore, "Hydration changed search rank or lost hasMore")
            try require(AppCoreMockProtocol.requests.first?.variables["query"] as? String == "test", "Search normalization not applied")
            try require(AppCoreMockProtocol.requests.count == 2, "Hydration fanned out per book")
        }
        await run("Search page append deduplicates and keeps status batching") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 42, "username": "fixture"]]]]) }
                if record.query == BookSearchAPI.statusQuery {
                    let ids = record.variables["ids"] as? [Int] ?? []
                    return .init(["data": ["user_books": ids.map { ["book_id": $0, "status_id": 1] }]])
                }
                let page = record.variables["page"] as? Int ?? 0
                let ids = page == 1 ? Array(1...25) : [25, 26]
                return .init(["data": ["search": ["ids": ids, "results": ids.map { ["id": $0, "title": "Book \($0)", "author_names": []] }]]])
            }
            let store = BookSearchStore()
            await store.search(.init(text: "pages", type: "Book", account: HardcoverConfig.authorizationHeaderValue), debounce: false)
            try require(store.books.count == 25 && store.hasMore && store.statuses.count == 25, "First search page incomplete")
            await store.loadMore()
            try require(store.books.count == 26 && Set(store.books.map(\.id)).count == 26 && !store.hasMore, "Search append lost pagination or duplicated books")
            try require(store.statuses.count == 26 && !store.isLoadingMore, "Second-page statuses not merged")
            try require(AppCoreMockProtocol.requests.filter { $0.query == BookSearchAPI.statusQuery }.count == 2, "Statuses not batched once per page")
        }
        await run("Library store paginates beyond 100 and caches only complete traversal") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 1, "username": "fixture"]]]]) }
                let offset = record.variables["offset"] as? Int ?? 0
                let limit = record.variables["limit"] as? Int ?? 0
                return .init(["data": ["user_books": (offset..<min(offset + limit, 125)).map { libraryRow(id: $0 + 1) }]])
            }
            let store = LibraryListStore(status: 2)
            await store.load()
            try require(store.books.count == 50 && store.hasMore && LibrarySnapshot.load(status: 2)?.complete == false, "First page incorrectly considered complete")
            await store.ensureAllLoaded()
            try require(store.books.count == 125 && !store.hasMore && store.error == nil, "Store truncated library beyond 100")
            try require(LibrarySnapshot.load(status: 2)?.complete == true && LibrarySnapshot.load(status: 2)?.books.count == 125, "Complete traversal not persisted")
            let count = AppCoreMockProtocol.requests.count
            await store.load()
            await store.loadMore()
            try require(AppCoreMockProtocol.requests.count == count, "Loaded store or final page refetched automatically")
        }
        await run("Want to Read release sorting includes later pages after initial load and refresh") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 1, "username": "fixture"]]]]) }
                let offset = record.variables["offset"] as? Int ?? 0
                let limit = record.variables["limit"] as? Int ?? 0
                let rows = (offset..<min(offset + limit, 125)).map { index -> [String: Any] in
                    var row = libraryRow(id: index + 1)
                    row["status_id"] = 1
                    var edition = row["edition"] as! [String: Any]
                    edition["release_date"] = index == 124 ? "2026-09-14" : "2026-10-01"
                    row["edition"] = edition
                    return row
                }
                return .init(["data": ["user_books": rows]])
            }
            let store = LibraryListStore(status: 1)
            for refresh in [false, true] {
                await store.load(refresh: refresh)
                await store.ensureAllLoaded()
                let sorted = WantToReadPresentation.books(store.books, query: "", filter: .all, sort: .nearestRelease,
                                                          now: ReleaseDate.parse("2026-09-13")!, timeZone: TimeZone(secondsFromGMT: 0)!)
                try require(sorted.count == 125 && sorted.first?.id == "125" && !store.hasMore,
                            "Nearest release on the third page was lost (refresh: \(refresh))")
            }
        }
        await run("Library store refresh failure preserves data and displays error") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 1, "username": "fixture"]]]]) }
                return .init(["data": ["user_books": [libraryRow(id: 7)]]])
            }
            let store = LibraryListStore(status: 2)
            await store.load()
            let snapshot = LibrarySnapshot.load(status: 2)!
            AppCoreMockProtocol.reset { _ in .init([:], status: 500) }
            await store.load(refresh: true)
            try require(store.books.map(\.id) == ["7"] && store.error != nil && !store.isLoading, "Refresh failure cleared visible library")
            try require(LibrarySnapshot.load(status: 2)?.date == snapshot.date, "Failed refresh rejuvenated snapshot")
            store.apply(book: store.books[0].withProgress(10))
            try require(LibrarySnapshot.load(status: 2)?.date == snapshot.date, "Local progress rejuvenated the entire snapshot")
        }
        await run("Library store reset rejects outstanding page") {
            AppGroup.useAccount()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 1, "username": "fixture"]]]]) }
                return .init(["data": ["user_books": [libraryRow(id: 7)]]], delay: 0.15)
            }
            let store = LibraryListStore(status: 2)
            let load = Task { await store.load() }
            try await eventually("Page not sent") { AppCoreMockProtocol.requests.contains { $0.query == LibraryAPI.pageQuery } }
            store.reset()
            await load.value
            try require(store.books.isEmpty && !store.isLoading && store.error == nil, "Reset repopulated by old request")
        }
        await run("Library store account change cannot persist old account books") {
            AppGroup.useAccount("store-old")
            LibrarySnapshot.clear()
            await HardcoverHTTP.shared.invalidate()
            AppCoreMockProtocol.reset { record in
                if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 1, "username": "fixture"]]]]) }
                return .init(["data": ["user_books": [libraryRow(id: 7)]]], delay: 0.15)
            }
            let store = LibraryListStore(status: 2)
            let load = Task { await store.load() }
            try await eventually("Account page not sent") { AppCoreMockProtocol.requests.contains { $0.query == LibraryAPI.pageQuery } }
            AppGroup.useAccount("store-new")
            await load.value
            try require(store.books.isEmpty && LibrarySnapshot.load(status: 2) == nil, "Old account's page leaked to new account")
        }
    }
}
