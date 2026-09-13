import Foundation

private enum CheckFailure: Error { case failed(String) }
private func check(_ value: Bool, _ message: String) throws {
    if !value { throw CheckFailure.failed(message) }
}
private func rejects(_ message: String, _ action: () throws -> Void) throws {
    do { try action() } catch { return }
    throw CheckFailure.failed(message)
}
private func rejectsAsync(_ message: String, _ action: () async throws -> Void) async throws {
    do { try await action() } catch { return }
    throw CheckFailure.failed(message)
}

private final class CatalogMockProtocol: URLProtocol {
    static var requests: [[String: Any]] = []
    static var headers: [String: String] = [:]
    static var handler: ([String: Any]) throws -> (Int, [String: Any]) = { _ in (500, [:]) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            Self.requests.append(body)
            let (status, json) = try Self.handler(body)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@main
struct CatalogEditingChecks {
    static let bookJSON = #"""
    {"id":10,"title":"A \"quoted\" book","description":"Original description","releaseDate":"2024-02-29","locked":false,
     "image":{"id":50,"url":"https://example.com/cover.jpg"},"defaultCoverEditionID":20,
     "defaultCoverEdition":{"id":20,"title":"An edition","isbn13":"9788888771426","readingFormat":{"id":4,"format":"Ebook"},"image":{"id":50,"url":"https://example.com/cover.jpg"}},
     "series":[{"id":30,"seriesID":40,"series":{"id":40,"name":"A series"},"position":1.5,"details":"Keep this detail","featured":true,"compilation":false}],
     "contributions":[{"id":1,"authorID":60,"author":{"id":60,"name":"Writer"},"contribution":null,"roleID":1,"specializationID":null}]}
    """#
    static let editionJSON = #"""
    {"id":20,"bookID":10,"title":"An edition","subtitle":null,"isbn10":null,"isbn13":"9788888771426","pages":194,
     "audioSeconds":null,"releaseDate":null,"readingFormatID":4,"editionFormat":"Digital","publisher":{"id":70,"name":"Publisher"},
     "image":{"id":50,"url":"https://example.com/cover.jpg"},"images":[{"id":50,"url":"https://example.com/cover.jpg"}],"locked":false,
     "contributions":[{"id":1,"authorID":60,"author":{"id":60,"name":"Writer"},"contribution":"Illustrator","roleID":2,"specializationID":5}]}
    """#

    static func object(_ string: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(string.utf8)) as! [String: Any]
    }

    static func main() async throws {
        if CommandLine.arguments.contains("--fixtures") {
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["book": object(bookJSON), "edition": object(editionJSON)]))
            return
        }
        if CommandLine.arguments.contains("--queries") {
            let queries = [CatalogService.bookQuery, CatalogService.editionQuery, CatalogService.editionsQuery,
                           CatalogService.rolesQuery, CatalogService.lookupsQuery, CatalogService.searchQuery,
                           CatalogService.overviewQuery, CatalogService.editionEditingQuery,
                           CatalogService.updateBookMutation, CatalogService.updateEditionMutation, CatalogService.importImageMutation,
                           CatalogService.EntityKind.author.query, CatalogService.EntityKind.series.query, CatalogService.EntityKind.publisher.query]
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: queries))
            return
        }
        let decoder = JSONDecoder()
        let book = try decoder.decode(CatalogBook.self, from: Data(bookJSON.utf8))
        let edition = try decoder.decode(CatalogEdition.self, from: Data(editionJSON.utf8))
        for value in [#"["librarian"]"#, #"["hardcover_admin"]"#, #"{"librarian":true}"#] {
            try check(try decoder.decode(CatalogRoles.self, from: Data(value.utf8)).canEdit, "Librarian role rejected")
        }
        for value in [#"[]"#, #"null"#, #"{"librarian":false}"#, #"["book_mapper"]"#, #"{"flair":"Librarian"}"#, #""librarian""#, #"["not_librarian"]"#] {
            try check(try !decoder.decode(CatalogRoles.self, from: Data(value.utf8)).canEdit, "Non-librarian role accepted")
        }
        try check(try CatalogBookDraft(book).patch(from: book).isEmpty, "Unchanged book produced a patch")
        try check(try CatalogEditionDraft(edition).patch(from: edition).isEmpty, "Unchanged edition produced a patch")

        let editionRoleNames = ["Author", "Illustrator", "Editor", "Translator", "Narrator", "Foreword", "Introduction", "Cover Artist", "Other"]
        let editorRoles = editionRoleNames.enumerated().map { CatalogEntity(id: 100 + $0.offset, name: $0.element) }
        let legacyRole = CatalogEntity(id: 500, name: "Art Director")
        let lookups = CatalogLookups(formats: [], roles: [legacyRole, CatalogEntity(id: 501, name: "Bibliographer"),
                                                       CatalogEntity(id: 502, name: nil)] + editorRoles.reversed())
        try check(lookups.editionContributorRoles.map(\.displayName) == editionRoleNames, "Edition roles differ from Hardcover or use registry ordering")
        try check(lookups.editionContributorRoles.map(\.id) == Array(100...108), "Edition role IDs were guessed or replaced")
        try check(lookups.roles.contains(legacyRole), "Filtering removed the original role needed for legacy display")
        let newContributor = CatalogContributorDraft(author: CatalogEntity(id: 62, name: "New author"), roleID: lookups.defaultContributorRoleID)
        try check(newContributor.roleID == 100, "New contributor does not default to the server's Author role")
        let missingRoles = CatalogLookups(formats: [], roles: [legacyRole])
        try check(missingRoles.editionContributorRoles.isEmpty && missingRoles.defaultContributorRoleID == nil, "Missing roles must not invent IDs or select a legacy role")
        let mixedCase = CatalogLookups(formats: [], roles: [CatalogEntity(id: 701, name: "author"), CatalogEntity(id: 702, name: "COVER ARTIST")])
        try check(mixedCase.editionContributorRoles.map(\.id) == [701, 702] && mixedCase.defaultContributorRoleID == 701, "Role matching is case sensitive")
        for roleID: Int? in [500, 999, nil] {
            var originalJSON = try object(editionJSON)
            var originalContributions = originalJSON["contributions"] as! [[String: Any]]
            originalContributions[0]["roleID"] = roleID as Any? ?? NSNull()
            originalJSON["contributions"] = originalContributions
            let original = try decoder.decode(CatalogEdition.self, from: JSONSerialization.data(withJSONObject: originalJSON))
            var preserved = CatalogEditionDraft(original)
            try check(try preserved.patch(from: original).isEmpty, "Legacy/unknown/missing role dirtied an unchanged edition")
            preserved.pages = "200"
            let pageDTO = try preserved.patch(from: original)["dto"] as! [String: Any]
            try check(pageDTO["contributions"] == nil, "Page change overwrote a legacy/unknown/missing role")
            preserved.contributors.append(newContributor)
            let roleDTO = try preserved.patch(from: original)["dto"] as! [String: Any]
            let inputs = roleDTO["contributions"] as! [[String: Any]]
            try check(inputs[0]["contributor_role_id"] as? Int == roleID, "Adding an author changed an existing role")
            try check(inputs[0]["contributor_specialization_id"] as? Int == 5 && inputs[0]["contribution"] as? String == "Illustrator", "Adding an author lost legacy contribution metadata")
            try check(inputs[1]["contributor_role_id"] as? Int == 100, "New author role not serialized")
            preserved.contributors[1].roleID = editorRoles.last!.id
            let otherDTO = try preserved.patch(from: original)["dto"] as! [String: Any]
            try check((otherDTO["contributions"] as! [[String: Any]])[1]["contributor_role_id"] as? Int == 108, "Other role not serialized")
        }
        print("PASS: edition role allowlist, server IDs, Author default, Other selection and legacy contribution preservation")

        var bookDraft = CatalogBookDraft(book)
        bookDraft.title = "New \"title\"\nSecond line"
        let titlePatch = try bookDraft.patch(from: book)
        let titleDTO = titlePatch["dto"] as! [String: Any]
        try check(Set(titleDTO.keys) == ["title"], "Title edit overwrote unrelated fields")
        _ = try JSONSerialization.data(withJSONObject: titlePatch)
        bookDraft.description = ""
        let clearDTO = try bookDraft.patch(from: book)["dto"] as! [String: Any]
        try check(clearDTO["description"] is NSNull, "Clearing a description must be explicit null")
        bookDraft.series[0].position = "2,5"
        let seriesDTO = try bookDraft.patch(from: book)["dto"] as! [String: Any]
        let series = (seriesDTO["series"] as! [[String: Any]])[0]
        try check(series["details"] as? String == "Keep this detail" && series["featured"] as? Bool == true, "Series metadata was lost")
        try check(series["position"] as? Double == 2.5, "Swedish decimal was not normalized")
        bookDraft.series = []
        try check((try bookDraft.patch(from: book)["dto"] as! [String: Any])["series"] as? [[String: Any]] != nil, "Series removal missing")

        var draft = CatalogEditionDraft(edition)
        draft.pages = "200"
        draft.readingFormatID = 1
        let editionDTO = try draft.patch(from: edition)["dto"] as! [String: Any]
        try check(editionDTO["page_count"] as? Int == 200 && editionDTO["pages"] == nil, "Wrong page mutation field")
        try check(editionDTO["reading_format_id"] as? Int == 1 && editionDTO["edition_format"] == nil, "Format confused with type")
        draft.contributors.append(CatalogContributorDraft(author: CatalogEntity(id: 61, name: "Another writer")))
        let contributorDTO = try draft.patch(from: edition)["dto"] as! [String: Any]
        let contributions = contributorDTO["contributions"] as! [[String: Any]]
        try check(contributions[0]["contributor_specialization_id"] as? Int == 5, "Specialization lost")
        try check(contributions[0]["contribution"] as? String == "Illustrator", "Contribution lost")
        try check(contributions[1]["author_id"] as? Int == 61, "Author selection not serialized")

        for formatID in [1, 4, 99] {
            var nonAudioJSON = try object(editionJSON)
            nonAudioJSON["readingFormatID"] = formatID
            nonAudioJSON["audioSeconds"] = 3600
            let nonAudio = try decoder.decode(CatalogEdition.self, from: JSONSerialization.data(withJSONObject: nonAudioJSON))
            var nonAudioDraft = CatalogEditionDraft(nonAudio)
            try check(!nonAudioDraft.isAudiobook, "Non-audio edition exposes audio length")
            nonAudioDraft.audioSeconds = "invalid hidden input"
            try check(try nonAudioDraft.patch(from: nonAudio).isEmpty, "Hidden audio field made a non-audio draft dirty")
            nonAudioDraft.title = "A corrected title"
            let dto = try nonAudioDraft.patch(from: nonAudio)["dto"] as! [String: Any]
            try check(Set(dto.keys) == ["title"], "Non-audio edit changed existing duration")
        }
        var audioJSON = try object(editionJSON)
        audioJSON["readingFormatID"] = 2
        audioJSON["audioSeconds"] = 3600
        let audiobook = try decoder.decode(CatalogEdition.self, from: JSONSerialization.data(withJSONObject: audioJSON))
        var audioDraft = CatalogEditionDraft(audiobook)
        try check(audioDraft.isAudiobook && (try audioDraft.patch(from: audiobook).isEmpty), "Unchanged audiobook draft is not clean")
        audioDraft.audioSeconds = "7200"
        let audioDTO = try audioDraft.patch(from: audiobook)["dto"] as! [String: Any]
        try check(audioDTO["audio_seconds"] as? Int == 7200, "Audiobook duration was not sent")
        audioDraft.audioSeconds = ""
        try check((try audioDraft.patch(from: audiobook)["dto"] as! [String: Any])["audio_seconds"] is NSNull, "Audio duration could not be cleared")
        audioDraft.audioSeconds = "-1"
        try rejects("Invalid audio duration accepted") { _ = try audioDraft.patch(from: audiobook) }
        audioDraft.audioSeconds = "7200"
        audioDraft.readingFormatID = 4
        try check(!audioDraft.isAudiobook, "Duration stayed visible after selecting ebook")
        let switchedDTO = try audioDraft.patch(from: audiobook)["dto"] as! [String: Any]
        try check(Set(switchedDTO.keys) == ["reading_format_id"], "Switching away from audio overwrote hidden duration")
        audioDraft.readingFormatID = 2
        try check(audioDraft.isAudiobook && audioDraft.audioSeconds == "7200", "Switching back lost the in-progress audio value")
        var newAudio = CatalogEditionDraft(edition)
        newAudio.readingFormatID = 2
        newAudio.audioSeconds = "900"
        let newAudioDTO = try newAudio.patch(from: edition)["dto"] as! [String: Any]
        try check(newAudioDTO["reading_format_id"] as? Int == 2 && newAudioDTO["audio_seconds"] as? Int == 900, "Converting to audio lost its duration")
        print("PASS: format-aware audio visibility, sparse duration patches, and format switching")

        _ = try CatalogValidation.date("2024-02-29")
        try rejects("Impossible date accepted") { _ = try CatalogValidation.date("2025-02-29") }
        try rejects("Wrong date format accepted") { _ = try CatalogValidation.date("2024-2-9") }
        for value in ["-1", "1.5", "2147483648", "abc"] {
            try rejects("Invalid integer accepted") { _ = try CatalogValidation.integer(value) }
        }
        for value in ["nan", "inf", "-2"] {
            try rejects("Invalid series position accepted") { _ = try CatalogValidation.position(value) }
        }
        _ = try CatalogValidation.isbn("978-0-306-40615-7", length: 13)
        _ = try CatalogValidation.isbn("0306406152", length: 10)
        try rejects("Bad ISBN checksum accepted") { _ = try CatalogValidation.isbn("9780306406158", length: 13) }
        try rejects("Insecure image URL accepted") { _ = try CatalogValidation.coverURL("http://example.com/image.jpg") }
        try rejects("Image credentials accepted") { _ = try CatalogValidation.coverURL("https://user:password@example.com/image.jpg") }
        print("PASS: role parsing, sparse patches, relation preservation, validation")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CatalogMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = CatalogService(authorization: "Bearer fixture", session: session, currentAuthorization: { "Bearer fixture" })
        let bookObject = try object(bookJSON)
        let editionObject = try object(editionJSON)
        var changedTitle = CatalogBookDraft(book)
        changedTitle.title = "Updated title"

        func install(roles: [String] = ["librarian"], bookResponse: [String: Any]? = nil,
                     editionResponse: [String: Any]? = nil, mutation: [String: Any] = ["id": 10, "errors": [], "warnings": []]) {
            CatalogMockProtocol.requests = []
            CatalogMockProtocol.headers = [:]
            CatalogMockProtocol.handler = { body in
                let query = body["query"] as! String
                if query.contains("CatalogRoles") { return (200, ["data": ["me": [["roles": roles]]]]) }
                if query.contains("query CatalogBook") { return (200, ["data": ["book": bookResponse ?? bookObject]]) }
                if query.contains("query CatalogEdition(") { return (200, ["data": ["edition": editionResponse ?? editionObject]]) }
                if query.contains("mutation") { return (200, ["data": ["result": mutation]]) }
                throw CheckFailure.failed("Unexpected query: \(query)")
            }
        }

        install(roles: [])
        try await rejectsAsync("Ordinary user saved catalog") { _ = try await service.saveBook(original: book, draft: changedTitle) }
        try check(CatalogMockProtocol.requests.count == 1, "Non-librarian mutation reached server")
        install()
        let warnings = try await service.saveBook(original: book, draft: changedTitle)
        try check(warnings.isEmpty, "Unexpected save warning")
        let sent = CatalogMockProtocol.requests.last!["variables"] as! [String: Any]
        try check(sent["id"] as? Int == book.id, "Wrong record updated")
        try check((sent["input"] as! [String: Any]).count == 1, "Unrelated book fields sent")

        var lockedBook = bookObject
        lockedBook["locked"] = true
        install(bookResponse: lockedBook)
        try await rejectsAsync("Locked record saved") { _ = try await service.saveBook(original: book, draft: changedTitle) }
        try check(CatalogMockProtocol.requests.count == 2, "Locked record mutation reached server")
        var staleBook = bookObject
        staleBook["title"] = "Somebody else's edit"
        install(bookResponse: staleBook)
        try await rejectsAsync("Concurrent edit overwritten") { _ = try await service.saveBook(original: book, draft: changedTitle) }
        try check(CatalogMockProtocol.requests.count == 2, "Conflicting mutation reached server")

        install(mutation: ["id": NSNull(), "errors": ["Permission denied"], "warnings": []])
        try await rejectsAsync("Nested mutation failure reported success") { _ = try await service.saveBook(original: book, draft: changedTitle) }
        install(mutation: ["id": NSNull(), "errors": [], "warnings": []])
        try await rejectsAsync("Missing confirmation reported success") { _ = try await service.saveBook(original: book, draft: changedTitle) }
        install(mutation: ["id": 10, "errors": [], "warnings": ["Normalization pending"]])
        try check(try await service.saveBook(original: book, draft: changedTitle) == ["Normalization pending"], "Warnings were hidden")

        install(mutation: ["id": 20, "errors": [], "warnings": []])
        _ = try await service.saveEdition(original: edition, draft: draft)
        let editionSent = CatalogMockProtocol.requests.last!["variables"] as! [String: Any]
        try check(editionSent["id"] as? Int == 20, "Wrong edition saved")
        install(roles: [])
        try await rejectsAsync("Unauthorized image import accepted") { _ = try await service.importCover(url: "https://example.com/new.jpg", original: edition) }
        try check(CatalogMockProtocol.requests.count == 1, "Unauthorized image import reached server")
        install(mutation: ["id": 99])
        try check(try await service.importCover(url: "https://example.com/new.jpg", original: edition) == 99, "Imported ID missing")
        let imageVariables = CatalogMockProtocol.requests.last!["variables"] as! [String: Any]
        let image = imageVariables["image"] as! [String: Any]
        try check(image["imageable_type"] as? String == "Edition" && image["imageable_id"] as? Int == 20, "Image associated with wrong record")

        install()
        var wrongCover = CatalogBookDraft(book)
        wrongCover.coverEditionID = 999
        var otherEdition = editionObject
        otherEdition["bookID"] = 11
        install(editionResponse: otherEdition)
        try await rejectsAsync("Another book's cover selected") { _ = try await service.saveBook(original: book, draft: wrongCover) }
        print("PASS: save authorization, locks, concurrent edits, nested errors, warnings, image import")

        CatalogMockProtocol.requests = []
        let switched = CatalogService(authorization: "Bearer fixture", session: session, currentAuthorization: { "Bearer changed" })
        try await rejectsAsync("Account switch accepted") { _ = try await switched.canEdit() }
        try check(CatalogMockProtocol.requests.isEmpty, "Old account request was sent")
        CatalogMockProtocol.handler = { _ in (403, ["error": "insufficient_scope", "error_description": "Missing write:catalog:edit"]) }
        try await rejectsAsync("Insufficient scope accepted") { _ = try await service.saveBook(original: book, draft: changedTitle) }
        CatalogMockProtocol.handler = { _ in (200, ["errors": [["message": "Scope error"]]]) }
        try await rejectsAsync("GraphQL error accepted") { _ = try await service.canEdit() }
        CatalogMockProtocol.handler = { body in
            let query = body["query"] as! String
            if query.contains("CatalogSearch") {
                let variables = body["variables"] as! [String: Any]
                try check(variables["query"] as? String == "A \"writer\"", "Search escaping broken")
                try check(variables["page"] as? Int == 2, "Search pagination broken")
                return (200, ["data": ["search": ["ids": [2, 1], "error": NSNull()]]])
            }
            return (200, ["data": ["entities": [["id": 1, "name": "One"], ["id": 2, "name": "Two"]]]])
        }
        let found = try await service.search("A \"writer\"", kind: .author, page: 2)
        try check(found.entities.map(\.id) == [2, 1], "Search ranking not preserved")
        print("PASS: account changes, scope errors, GraphQL errors, ranked and paginated search")

        var overviewBook = bookObject
        overviewBook["editions"] = [bookObject["defaultCoverEdition"]!]
        let overviewData: [String: Any] = ["me": [["roles": ["librarian"]]], "book": overviewBook]
        CatalogMockProtocol.requests = []
        CatalogMockProtocol.handler = { body in
            try check((body["query"] as! String).contains("CatalogOverview"), "Editor made a separate loading request")
            try check((body["variables"] as! [String: Any])["id"] as? Int == 10, "Wrong overview book")
            return (200, ["data": overviewData])
        }
        let overview = try await service.editorOverview(bookID: 10)
        try check(overview.book == book && overview.editions.map(\.id) == [20], "Overview did not decode book and editions")
        try check(CatalogMockProtocol.requests.count == 1, "Overview should use one HTTP request")
        CatalogMockProtocol.handler = { _ in (200, ["data": ["me": [["roles": []]], "book": overviewBook]]) }
        try await rejectsAsync("Overview admitted an ordinary account") { _ = try await service.editorOverview(bookID: 10) }
        CatalogMockProtocol.requests = []
        CatalogMockProtocol.handler = { body in
            try check((body["query"] as! String).contains("CatalogEditionEditing"), "Edition lookups fetched separately")
            try check((body["variables"] as! [String: Any])["id"] as? Int == 20, "Wrong selected edition")
            return (200, ["data": ["edition": editionObject, "formats": [["id": 4, "format": "Ebook"]], "roles": [["id": 1, "name": "Author"]]]])
        }
        let editing = try await service.editionEditingData(id: 20)
        try check(editing.edition == edition && editing.lookups.formats.first?.id == 4, "Edition editing data mismatch")
        try check(CatalogMockProtocol.requests.count == 1, "Edition should load in one HTTP request")
        print("PASS: consolidated overview, lazy edition data, and overview authorization")

        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        var instant = epoch
        var waits: [TimeInterval] = []
        var account = "Bearer fixture"
        var limited = service
        limited.requestGate = CatalogRequestGate()
        limited.now = { instant }
        limited.sleep = { seconds in waits.append(seconds); instant = instant.addingTimeInterval(seconds) }
        limited.currentAuthorization = { account }
        let roleData: [String: Any] = ["data": ["me": [["roles": ["librarian"]]]]]
        CatalogMockProtocol.requests = []
        CatalogMockProtocol.headers = ["Retry-After": "7"]
        CatalogMockProtocol.handler = { _ in CatalogMockProtocol.requests.count == 1 ? (429, [:]) : (200, roleData) }
        try check(try await limited.canEdit(), "Read failed after rate limit cleared")
        try check(waits == [7] && CatalogMockProtocol.requests.count == 2, "Read did not honor Retry-After")

        CatalogMockProtocol.requests = []
        waits = []
        CatalogMockProtocol.handler = { _ in (429, [:]) }
        try await rejectsAsync("Repeated 429 retried without bound") { _ = try await limited.canEdit() }
        try check(CatalogMockProtocol.requests.count == 2 && waits == [7], "Read retry limit broken")
        CatalogMockProtocol.requests = []
        waits = []
        CatalogMockProtocol.handler = { _ in (200, roleData) }
        _ = try await limited.canEdit()
        try check(waits == [7] && CatalogMockProtocol.requests.count == 1, "Next request ignored shared cooldown")

        for header in [nil, "invalid", "-10", "nan"] as [String?] {
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil,
                                           headerFields: header.map { ["Retry-After": $0] })!
            try check(CatalogService.retryDate(response: response, now: epoch) == epoch.addingTimeInterval(60), "Invalid retry header fallback")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let dateHeader = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil,
                                        headerFields: ["Retry-After": formatter.string(from: epoch.addingTimeInterval(30))])!
        try check(CatalogService.retryDate(response: dateHeader, now: epoch) == epoch.addingTimeInterval(30), "HTTP-date Retry-After not honored")

        CatalogMockProtocol.requests = []
        waits = []
        CatalogMockProtocol.headers = ["Retry-After": "86400"]
        CatalogMockProtocol.handler = { _ in (429, [:]) }
        try await rejectsAsync("Daily limit waited indefinitely") { _ = try await limited.canEdit() }
        try await rejectsAsync("Manual retry ignored daily cooldown") { _ = try await limited.canEdit() }
        try check(CatalogMockProtocol.requests.count == 1 && waits.isEmpty, "Daily quota caused repeated requests")
        let otherAccount = CatalogService(authorization: "Bearer another", session: session,
                                          currentAuthorization: { "Bearer another" }, requestGate: limited.requestGate,
                                          now: { instant }, sleep: limited.sleep)
        CatalogMockProtocol.handler = { _ in (200, roleData) }
        _ = try await otherAccount.canEdit()
        try check(CatalogMockProtocol.requests.count == 2, "Cooldown leaked across accounts")

        limited.requestGate = CatalogRequestGate()
        CatalogMockProtocol.requests = []
        CatalogMockProtocol.headers = ["Retry-After": "5"]
        CatalogMockProtocol.handler = { _ in (429, [:]) }
        limited.sleep = { _ in throw CancellationError() }
        try await rejectsAsync("Cancelled retry continued") { _ = try await limited.canEdit() }
        try check(CatalogMockProtocol.requests.count == 1, "Cancelled request retried")
        limited.requestGate = CatalogRequestGate()
        CatalogMockProtocol.requests = []
        limited.sleep = { seconds in instant = instant.addingTimeInterval(seconds); account = "Bearer changed" }
        try await rejectsAsync("Account change during cooldown retried") { _ = try await limited.canEdit() }
        try check(CatalogMockProtocol.requests.count == 1, "Old account request sent after waiting")

        account = "Bearer fixture"
        limited.requestGate = CatalogRequestGate()
        limited.sleep = { seconds in waits.append(seconds); instant = instant.addingTimeInterval(seconds) }
        install()
        waits = []
        CatalogMockProtocol.headers = ["Retry-After": "5"]
        let normalHandler = CatalogMockProtocol.handler
        CatalogMockProtocol.handler = { body in
            if (body["query"] as! String).contains("mutation") { return (429, [:]) }
            return try normalHandler(body)
        }
        try await rejectsAsync("Rate-limited mutation reported success") { _ = try await limited.saveBook(original: book, draft: changedTitle) }
        try check(CatalogMockProtocol.requests.count == 3 && waits.isEmpty, "Mutation was automatically replayed")
        limited.requestGate = CatalogRequestGate()
        CatalogMockProtocol.requests = []
        try await rejectsAsync("Rate-limited image import reported success") { _ = try await limited.importCover(url: "https://example.com/image.jpg", original: edition) }
        try check(CatalogMockProtocol.requests.count == 3 && waits.isEmpty, "Image import was automatically replayed")
        print("PASS: 429 recovery, cooldown isolation, bounded retries, cancellation, and no mutation replay")
        print("All catalog editing checks passed.")
    }
}
