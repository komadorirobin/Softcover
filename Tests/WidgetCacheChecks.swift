@main
struct WidgetCacheChecks {
    static func require(_ value: Bool, _ message: String) {
        guard value else { fatalError(message) }
    }

    static func book() -> BookProgress {
        BookProgress(id: "42", title: "Test Book", author: "Author", coverImageData: Data([1, 2, 3]), coverImageUrl: "https://example.invalid/cover.jpg", progress: 0.1, totalPages: 100, currentPage: 10, bookId: 99, userBookId: 42, editionId: 5, originalTitle: "Test Book", statusId: 2)
    }

    static func main() async throws {
        defer { AppGroup.defaults.removePersistentDomain(forName: AppGroup.suite) }
        HardcoverConfig.apiKey = "account-a"
        try await widgetChecks()
        try await diskChecks()
        print("PASS: widget cache, selective sync, account isolation, last-good fallback, deep links, disk freshness/LRU/bounds")
    }

    static func widgetChecks() async throws {
        let reading = WidgetSync.readingKind
        let goal = WidgetSync.goalKind
        let token = WidgetSnapshotStore.token(kind: reading)
        require(WidgetSnapshotStore.save([book()], token: token), "save snapshot")
        require(WidgetSnapshotStore.load([BookProgress].self, token: token, maxAge: 300, fresh: true)?.payload.count == 1, "fresh snapshot")
        WidgetSnapshotStore.invalidate(kind: reading)
        let newer = WidgetSnapshotStore.token(kind: reading)
        require(WidgetSnapshotStore.load([BookProgress].self, token: newer, maxAge: 300, fresh: true) == nil, "invalidated data is not fresh")
        require(WidgetSnapshotStore.load([BookProgress].self, token: newer, maxAge: 300)?.payload.count == 1, "invalidated data remains last-good")
        require(!WidgetSnapshotStore.save([book()], token: token), "late response cannot replace invalidated cache")
        HardcoverConfig.apiKey = "account-b"
        require(WidgetSnapshotStore.load([BookProgress].self, token: token, maxAge: 300) == nil, "old account cannot load")
        require(!WidgetSnapshotStore.save([book()], token: token), "old account cannot save")
        require(WidgetSnapshotStore.load([BookProgress].self, token: WidgetSnapshotStore.token(kind: reading), maxAge: 300) == nil, "new account cannot see prior data")
        HardcoverConfig.apiKey = "account-a"
        let beforeReset = WidgetSnapshotStore.token(kind: goal)
        WidgetSnapshotStore.clear()
        require(beforeReset != WidgetSnapshotStore.token(kind: goal), "reset invalidates even the same account")
        require(!WidgetSnapshotStore.save(String(repeating: "x", count: 2_200_000), token: WidgetSnapshotStore.token(kind: goal)), "snapshot bounded")

        LibrarySnapshot.save([book()], status: 2, complete: false)
        LibrarySnapshot.save([], status: 1, complete: true)
        WidgetSnapshotStore.save([book()], token: WidgetSnapshotStore.token(kind: reading))
        let libraryDate = LibrarySnapshot.load(status: 2)!.date
        let widgetDate = WidgetSnapshotStore.load([BookProgress].self, token: WidgetSnapshotStore.token(kind: reading), maxAge: 300)!.date
        var updated = book().withProgress(23)
        updated.coverImageData = nil
        WidgetSync.progressChanged(book: updated)
        let patchedLibrary = LibrarySnapshot.load(status: 2)!
        let patchedWidget = WidgetSnapshotStore.load([BookProgress].self, token: WidgetSnapshotStore.token(kind: reading), maxAge: 300)!
        require(patchedLibrary.books[0].currentPage == 23 && patchedLibrary.date == libraryDate && !patchedLibrary.complete, "progress preserves snapshot age and completeness")
        require(patchedWidget.payload[0].currentPage == 23 && patchedWidget.payload[0].coverImageData != nil && patchedWidget.date == widgetDate, "patch preserves widget cover and snapshot age")
        require(LibrarySnapshot.load(status: 1)?.stale == false, "progress leaves want-to-read intact")
        WidgetSync.libraryChanged(statuses: [1])
        require(LibrarySnapshot.load(status: 1)?.stale == true, "only changed library invalidated")
        require(LibrarySnapshot.load(status: 2)?.stale == false, "unaffected library stays fresh")
        let selected = try await WidgetReaders.selectedBooks(ids: ["42"])
        require(selected.first?.currentPage == 23, "manual selection resolves from app snapshot")
        let variant = WidgetSnapshotStore.token(kind: reading, variant: "manual-test")
        require(WidgetSnapshotStore.save([book()], token: variant), "manual widget variant saved")
        WidgetSync.progressChanged(book: updated)
        let manualPatched = WidgetSnapshotStore.load([BookProgress].self, token: WidgetSnapshotStore.token(kind: reading, variant: "manual-test"), maxAge: 300)
        require(manualPatched?.payload.first?.currentPage == 23, "manual widget variants receive local progress")
        require(WidgetSync.kindsForLibraryChange(statuses: [1]) == [WidgetSync.upcomingKind], "want-to-read reloads only upcoming")
        require(WidgetSync.kindsForLibraryChange(statuses: [2]) == [reading, goal], "reading change excludes quote and upcoming")
        let recorder = ReloadRecorder()
        let coordinator = WidgetReloadCoordinator(delay: 60, reload: { recorder.reload($0) }, notify: { recorder.notify($0) })
        for _ in 0..<100 { coordinator.request(kinds: [reading, goal], statuses: [2]) }
        coordinator.request(kinds: [reading], statuses: [3])
        coordinator.flush()
        let recorded = recorder.snapshot()
        require(recorded.0.count == 2 && Set(recorded.0) == [reading, goal], "reloads coalesced by kind")
        require(recorded.1 == [[2, 3]], "one library notification per batch")

        let goalLink = URLComponents(url: WidgetDeepLink.goal(id: 23), resolvingAgainstBaseURL: false)!
        require(goalLink.host == "goals" && goalLink.queryItems?.first?.value == "23", "specific goal link")
        let releaseLink = URLComponents(url: WidgetDeepLink.upcoming(bookID: 123, editionID: 456), resolvingAgainstBaseURL: false)!
        require(releaseLink.queryItems?.map(\.name) == ["bookId", "editionId"], "release link includes book and edition")
        require(WidgetDeepLink.upcoming(bookID: nil, editionID: nil).absoluteString == "softcover://upcoming", "empty release link remains valid")

        WidgetSnapshotStore.invalidate(kind: goal)
        await WidgetBackend.shared.configure(delay: 80_000_000)
        async let first = WidgetReaders.goals()
        async let second = WidgetReaders.goals()
        let loaded = await (first, second)
        require(loaded.0.value.first?.id == 1 && !loaded.1.failed, "goals successful")
        require(await WidgetBackend.shared.count() == 1, "concurrent widget reads coalesced")
        _ = await WidgetReaders.goals()
        require(await WidgetBackend.shared.count() == 1, "fresh goals do not request network again")
        WidgetSnapshotStore.invalidate(kind: goal)
        await WidgetBackend.shared.configure(fail: true)
        let failed = await WidgetReaders.goals()
        require(failed.failed && failed.value.first?.id == 1, "typed failure retains last-good goals")
        WidgetSnapshotStore.invalidate(kind: goal)
        await WidgetBackend.shared.configure(values: [])
        let empty = await WidgetReaders.goals()
        require(!empty.failed && empty.value.isEmpty, "legitimate empty result replaces cache")
        WidgetSnapshotStore.invalidate(kind: goal)
        await WidgetBackend.shared.configure(values: [ReadingGoal(id: 9)], delay: 80_000_000)
        let delayed = Task { await WidgetReaders.goals() }
        try await Task.sleep(nanoseconds: 20_000_000)
        HardcoverConfig.apiKey = "account-c"
        let switched = await delayed.value
        require(switched.value.isEmpty && switched.failed, "in-flight account switch cannot reveal prior account")
        HardcoverConfig.apiKey = "account-a"
        let valid = Data(#"{"data":{"reading_journals":[]}}"#.utf8)
        require(try WidgetReaders.decodeQuotes(valid).isEmpty, "valid empty quotes accepted")
        do {
            _ = try WidgetReaders.decodeQuotes(Data(#"{"data":{}}"#.utf8))
            fatalError("malformed quote payload accepted")
        } catch {}

        let agedToken = WidgetSnapshotStore.token(kind: reading, variant: "aged")
        WidgetSnapshotStore.save([book()], token: agedToken, date: Date().addingTimeInterval(-86401))
        require(WidgetSnapshotStore.load([BookProgress].self, token: agedToken, maxAge: 86400) == nil, "last-good data has an explicit age bound")
        for index in 0..<16 {
            let token = WidgetSnapshotStore.token(kind: reading, variant: "bounded-\(index)")
            WidgetSnapshotStore.save([book()], token: token)
        }
        let snapshots = AppGroup.defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("WidgetSnapshot.v1.") && $0.value is Data }
        require(snapshots.count <= 12, "manual-selection caches have a global account bound")
        let calendar = Calendar.current
        let reference = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: reference)!
        let target = calendar.date(byAdding: .day, value: 2, to: reference)!
        require(daysUntil(target, relativeTo: reference) == 2 && daysUntil(target, relativeTo: nextDay) == 1, "countdown uses timeline date, including future entries")
    }

    static func diskChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageCacheChecks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock()
        let cache = DiskCache(folderURL: directory, now: { clock.now() })
        await cache.configure(ttl: 60, maxSizeBytes: 1_048_576)
        await cache.storeData(Data([1, 2, 3]), forKey: "freshness")
        clock.advance(50)
        require(await cache.loadData(forKey: "freshness") == Data([1, 2, 3]), "fresh image data readable")
        clock.advance(11)
        require(await cache.loadData(forKey: "freshness") == nil, "reading does not renew freshness")
        await cache.removeAll()
        await cache.configure(ttl: 3600, maxSizeBytes: 1_048_576)
        let bytes = Data(repeating: 7, count: 400_000)
        await cache.storeData(bytes, forKey: "first")
        clock.advance(1)
        await cache.storeData(bytes, forKey: "second")
        clock.advance(1)
        _ = await cache.loadData(forKey: "first")
        clock.advance(1)
        await cache.storeData(bytes, forKey: "third")
        try await Task.sleep(nanoseconds: 2_200_000_000)
        require(await cache.loadData(forKey: "second") == nil, "LRU removes least recently accessed")
        let firstRetained = await cache.loadData(forKey: "first") != nil
        let thirdRetained = await cache.loadData(forKey: "third") != nil
        require(firstRetained && thirdRetained, "LRU retains recent entries")
        let reloaded = DiskCache(folderURL: directory, now: { clock.now() })
        require(await reloaded.loadData(forKey: "first") == bytes, "disk index survives process-style reload")
        await cache.storeData(Data(repeating: 1, count: 2_000_000), forKey: "oversized")
        require(await cache.loadData(forKey: "oversized") == nil, "oversized files not cached")
        await cache.removeAll()
        let start = Date()
        for index in 0..<200 { await cache.storeData(Data(repeating: 1, count: 128), forKey: "burst-\(index)") }
        let milliseconds = Date().timeIntervalSince(start) * 1000
        print(String(format: "Disk cache: 200 accounted writes in %.1f ms (isolated Mac test)", milliseconds))
        require(await cache.loadData(forKey: "burst-199")?.count == 128, "burst writes retained")
        await cache.removeAll()
        require(await cache.loadData(forKey: "burst-199") == nil, "clear removes indexed data")
    }

}
