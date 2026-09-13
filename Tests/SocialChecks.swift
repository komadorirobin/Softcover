import Foundation

@main
struct SocialChecks {
    @MainActor static func main() async throws {
        AppGroup.reset()
        defer { AppGroup.reset(); URLProtocol.unregisterClass(AppCoreMockProtocol.self) }
        guard URLProtocol.registerClass(AppCoreMockProtocol.self) else {
            throw AppCoreCheckFailure(description: "Cannot intercept networking")
        }
        AppCoreMockProtocol.reset { _ in .init(["intercepted": true]) }
        _ = try await URLSession.shared.data(from: URL(string: "https://softcover-tests.invalid/preflight")!)
        try socialRequire(AppCoreMockProtocol.requests.count == 1, "Refusing tests without fail-closed network interception")

        try checkHTML()
        try checkHistoryMapping()
        try await checkUpcomingFailures()
        try await checkPromptFailures()
        try await checkExploreStore()
        try await checkHistoryStore()
        print("PASS social/prompt parsing, upcoming errors, history paging/cancellation and Explore races")
    }

    static func checkHTML() throws {
        for html in ["", "<html>Sign in</html>", try socialHTML([:]), try socialHTML(["lists": "changed schema"])] {
            try socialRequire(HardcoverService.extractCommunityListsFromHTML(html) == nil, "Malformed list page treated as empty")
        }
        try socialRequire(HardcoverService.extractCommunityListsFromHTML(try socialHTML(["lists": []]))?.isEmpty == true, "Successful empty list rejected")
        let list: [String: Any] = ["id": 7, "name": "Fixture list", "booksCount": 1,
            "user": ["username": "reader"], "listBooks": [["editionId": 70, "book": ["id": 700, "title": "A Book", "image": ["url": "https://images.invalid/a.jpg"]]]]]
        let parsed = HardcoverService.extractCommunityListsFromHTML(try socialHTML(["lists": [list]]))
        try socialRequire(parsed?.first?.id == 7 && parsed?.first?.books.first?.bookId == 700, "List fixture mapping changed")
        try socialRequire(HardcoverService.extractCommunityListsFromHTML(try socialHTML(["lists": [["wrong": 1]]])) == nil, "Invalid row silently dropped")
        try socialRequire(HardcoverService.extractListsFromHTML(try socialHTML(["lists": []]))?.isEmpty == true, "Empty user lists rejected")
        try socialRequire(HardcoverService.extractListBooksFromHTML(try socialHTML(["letterbooks": ["data": []]]))?.isEmpty == true, "Empty paginated list rejected")
        try socialRequire(HardcoverService.extractListBooksFromHTML(try socialHTML(["books": [["wrong": 1]]])) == nil, "Malformed list book dropped")

        try socialRequire(HardcoverGoalPage.decode(try socialHTML(["goals": []]))?.isEmpty == true, "Valid empty goals must clear snapshots")
        for html in ["", "<html>Sign in</html>", try socialHTML([:]), try socialHTML(["goals": [["id": 1]]])] {
            try socialRequire(HardcoverGoalPage.decode(html) == nil, "Unreadable goals must preserve snapshots")
        }
        let goal: [String: Any] = ["id": 1, "goal": 50, "metric": "book", "endDate": "2026-12-31", "startDate": "2026-01-01", "progress": 12, "percentComplete": 0.24, "privacySettingId": 1, "archived": false]
        try socialRequire(HardcoverGoalPage.decode(try socialHTML(["goals": [goal]]))?.first?.progress == 12, "Valid goal fixture failed")
        try socialRequire(HardcoverGoalPage.decode(try socialHTML(["goals": [goal, ["id": 2]]])) == nil, "Partially malformed goals must fail atomically")
    }

    static func checkHistoryMapping() throws {
        let data = try JSONSerialization.data(withJSONObject: ["data": ["user_book_reads": [historyRow(1), historyRow(2), historyRow(3)]]])
        let page = try LibraryHistoryAPI.decode(data, offset: 10, limit: 2)
        try socialRequire(page.entries.count == 2 && page.nextOffset == 12 && page.hasMore, "History raw page boundary wrong")
        try socialRequire(page.entries[0].title == "Edition 1" && page.entries[0].coverImageUrl == "https://images.invalid/edition.jpg", "Edition mapping lost")
        try socialRequire(page.entries[0].coverImageData == nil, "History should not download covers before displaying")
        let empty = try LibraryHistoryAPI.decode(JSONSerialization.data(withJSONObject: ["data": ["user_book_reads": []]]), offset: 25, limit: 25)
        try socialRequire(!empty.hasMore && empty.nextOffset == 25, "Empty last page wrong")
        do {
            _ = try LibraryHistoryAPI.decode(JSONSerialization.data(withJSONObject: ["data": ["user_book_reads": [["id": 1]]]]), offset: 0, limit: 25)
            throw AppCoreCheckFailure(description: "Malformed history accepted")
        } catch is HardcoverNetworkError { }
    }

    static func checkUpcomingFailures() async throws {
        AppGroup.useAccount()
        await HardcoverHTTP.shared.invalidate()
        AppCoreMockProtocol.reset { record in
            try socialRequire(record.variables["start"] as? String == "2026-09-13", "Missing selected lower bound")
            try socialRequire(record.variables["end"] as? String == "2026-10-13", "Missing selected upper bound")
            if record.query == CommunityQueries.upcomingBooks { return .init(["data": ["books": []]]) }
            try socialRequire(record.query == CommunityQueries.upcomingEditions, "Unexpected fallback query")
            return .init(["data": ["editions": []]])
        }
        let books = try await HardcoverService.communityUpcomingReleases(filter: "month", now: ReleaseDate.parse("2026-09-13")!)
        try socialRequire(books.isEmpty && AppCoreMockProtocol.requests.count == 2, "Empty books should use interval-bounded editions fallback")
        await HardcoverHTTP.shared.invalidate()
        AppCoreMockProtocol.reset { _ in .init(["errors": [["message": "Fixture failure"]]]) }
        try await requireError("Upcoming error must not silently use empty fallback") {
            _ = try await HardcoverService.communityUpcomingReleases(filter: "year")
        }
        try socialRequire(AppCoreMockProtocol.requests.count == 1, "Fallback should not hide original error")
        AppGroup.useAccount()
        await HardcoverHTTP.shared.invalidate()
        AppCoreMockProtocol.reset { _ in .init(raw: "<html>Changed list markup</html>") }
        try await requireError("Legacy list parser must record invalid response") {
            _ = try await HardcoverReadScope.checked { await HardcoverService.fetchUserLists(username: "fixture") }
        }
    }

    @MainActor static func checkExploreStore() async throws {
        AppGroup.useAccount()
        let store = ExploreLoadState<Int>()
        let slow = Task { await store.load(key: "A") { try? await Task.sleep(for: .milliseconds(60)); return [1] } }
        try await Task.sleep(for: .milliseconds(5))
        await store.load(key: "B") { [2] }
        await slow.value
        try socialRequire(store.items == [2], "Older Explore response replaced current filter")
        await store.load(key: "B", refresh: true) { throw HardcoverNetworkError.server(500) }
        try socialRequire(store.items == [2] && store.error != nil, "Refresh error erased last good content")
        await store.load(key: "B") { throw AppCoreCheckFailure(description: "Cached filter refetched") }
        try socialRequire(store.items == [2] && store.error == nil, "Cached filter not reused")
        let cancelled = Task { await store.load(key: "C") { try? await Task.sleep(for: .milliseconds(40)); return [3] } }
        try await Task.sleep(for: .milliseconds(5)); cancelled.cancel(); await cancelled.value
        try socialRequire(store.items == [2] && !store.isLoading, "Cancelled load published or stuck loading")
        AppGroup.useAccount()
        await store.load(key: "B") { [4] }
        try socialRequire(store.items == [4], "Account reused prior-account filter cache")
    }

    static func checkPromptFailures() async throws {
        AppGroup.useAccount()
        await HardcoverHTTP.shared.invalidate()
        AppCoreMockProtocol.reset { _ in .init(["data": ["unexpected": []]]) }
        try await requireError("Malformed prompt GraphQL must not become empty") {
            _ = try await HardcoverReadScope.checked {
                await HardcoverService.fetchAnsweredPrompts(forUsername: "fixture")
            }
        }
        await HardcoverHTTP.shared.invalidate()
        AppCoreMockProtocol.reset { _ in .init(["data": ["prompt_answers": []]]) }
        let empty = try await HardcoverReadScope.checked {
            await HardcoverService.fetchAnsweredPrompts(forUsername: "fixture")
        }
        try socialRequire(empty.isEmpty, "Valid empty prompts should succeed")

        AppGroup.useAccount()
        await HardcoverHTTP.shared.invalidate()
        AppCoreMockProtocol.reset { _ in .init(raw: "<html>Changed prompt markup</html>") }
        try await requireError("Malformed prompt HTML must not become empty") {
            _ = try await HardcoverReadScope.checked {
                await HardcoverService.fetchPromptAnswers(promptId: 1, userId: 1, username: "fixture", slug: "question")
            }
        }
        await HardcoverHTTP.shared.invalidate()
        let emptyHTML = try socialHTML(["prompt": ["promptBooks": []]])
        AppCoreMockProtocol.reset { _ in .init(raw: emptyHTML) }
        let answers = try await HardcoverReadScope.checked {
            await HardcoverService.fetchPromptAnswers(promptId: 1, userId: 1, username: "fixture", slug: "question")
        }
        try socialRequire(answers.first?.books.isEmpty == true, "Valid empty prompt answer should succeed")
    }

    @MainActor static func checkHistoryStore() async throws {
        AppGroup.useAccount()
        await HardcoverHTTP.shared.invalidate()
        AppCoreMockProtocol.reset { record in
            if record.query == LibraryAPI.identityQuery { return .init(["data": ["me": [["id": 1, "username": "reader"]]]]) }
            let offset = record.variables["offset"] as? Int ?? -1
            if offset == 0 { return .init(["data": ["user_book_reads": (1...26).map(historyRow)]]) }
            try socialRequire(offset == 25, "Cancelled search restarted cached pages")
            return .init(["data": ["user_book_reads": [historyRow(26), historyRow(27)]]], delay: 0.2)
        }
        let store = HistoryListStore()
        await store.load()
        try socialRequire(store.entries.count == 25 && store.hasMore, "First history page incomplete")
        let search = Task { await store.ensureAllLoaded() }
        while !AppCoreMockProtocol.requests.contains(where: { $0.variables["offset"] as? Int == 25 }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        search.cancel(); await search.value
        try socialRequire(store.hasMore && store.entries.count == 25, "Cancelled history marked complete")
        await store.ensureAllLoaded()
        try socialRequire(!store.hasMore && store.entries.count == 27, "Resumed history missing final page")
        try socialRequire(AppCoreMockProtocol.requests.filter { $0.variables["offset"] as? Int == 0 }.count == 1, "Search refetched cached page zero")
        await HardcoverHTTP.shared.invalidate()
        AppCoreMockProtocol.reset { _ in .init(["errors": [["message": "Refresh failed"]]]) }
        await store.load(refresh: true)
        try socialRequire(store.entries.count == 27 && store.error != nil, "History refresh erased existing entries")
    }
}
