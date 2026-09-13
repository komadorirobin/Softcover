import SwiftUI
import Foundation

enum HardcoverConfig {
    static var authorizationHeaderValue: String {
        "Bearer " + (UserDefaults.standard.string(forKey: "HardcoverAPIKey") ?? "")
    }
}
enum AppGroup { static let defaults = UserDefaults.standard }

final class ToolbarFixtureProtocol: URLProtocol {
    static let requestCountKey = "CatalogToolbarFixtureRequests"
    static var overviewRequests = 0
    static var editionRequests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        DispatchQueue.main.async {
            let defaults = UserDefaults.standard
            defaults.set(defaults.integer(forKey: Self.requestCountKey) + 1, forKey: Self.requestCountKey)
        }
        let mode = CommandLine.arguments.contains("denied") ? "denied" : CommandLine.arguments.contains("scope-error") ? "scope-error" : "librarian"
        let beforeSwitch = CommandLine.arguments.contains("switch-account") && request.value(forHTTPHeaderField: "Authorization") == "Bearer toolbar-fixture"
        let roles: [String] = mode == "denied" || beforeSwitch ? [] : ["librarian"]
        var body: [String: Any] = mode == "scope-error"
            ? ["error": "insufficient_scope", "error_description": "Missing read:me:roles"]
            : ["data": ["me": [["roles": roles]]]]
        var status = mode == "scope-error" ? 403 : 200
        var headers: [String: String] = [:]
        if CommandLine.arguments.contains(where: { $0.hasPrefix("editor") || $0.hasPrefix("edition") }) {
            let data: Data
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var collected = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    collected.append(contentsOf: buffer.prefix(count))
                }
                data = collected
            } else { data = request.httpBody ?? Data() }
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let query = payload?["query"] as? String ?? ""
            let fixtureURL = Bundle.main.url(forResource: "catalog-fixtures", withExtension: "json")!
            let fixtures = try! JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
            var book = fixtures["book"] as! [String: Any]
            var edition = fixtures["edition"] as! [String: Any]
            book["image"] = NSNull()
            book["defaultCoverEdition"] = NSNull()
            edition["image"] = NSNull()
            edition["images"] = []
            if CommandLine.arguments.contains("edition-audio") {
                edition["readingFormatID"] = 2
                edition["audioSeconds"] = 3600
            } else if CommandLine.arguments.contains("edition-physical") {
                edition["readingFormatID"] = 1
            }
            let summaries: [[String: Any]] = [
                ["id": 20, "title": "Example book - digital edition", "isbn13": "9788888771426", "readingFormat": ["id": 4, "format": "Ebook"]],
                ["id": 21, "title": "Example book - printed edition", "isbn13": "9780306406157", "readingFormat": ["id": 1, "format": "Physical"]]
            ]
            if query.contains("CatalogOverview") {
                Self.overviewRequests += 1
                book["editions"] = summaries
                body = ["data": ["me": [["roles": ["librarian"]]], "book": book]]
            } else if query.contains("CatalogEditionEditing") {
                Self.editionRequests += 1
                body = ["data": ["edition": edition, "formats": [["id": 4, "format": "Ebook"], ["id": 1, "format": "Physical"], ["id": 2, "format": "Audio"]],
                                 "roles": [["id": 1, "name": "Author"], ["id": 2, "name": "Illustrator"]]]]
            }
            let throttleOverview = query.contains("CatalogOverview") && Self.overviewRequests == 1 && CommandLine.arguments.contains("editor-rate-limit")
            let throttleEdition = query.contains("CatalogEditionEditing") && Self.editionRequests == 1 && CommandLine.arguments.contains("edition-rate-limit")
            if throttleOverview || throttleEdition || CommandLine.arguments.contains("editor-daily-limit") {
                status = 429
                headers["Retry-After"] = CommandLine.arguments.contains("editor-daily-limit") ? "86400" : "5"
                body = ["error": "Too Many Requests"]
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main
struct CatalogToolbarFixture: App {
    init() {
        UserDefaults.standard.set("toolbar-fixture", forKey: "HardcoverAPIKey")
        UserDefaults.standard.set(0, forKey: ToolbarFixtureProtocol.requestCountKey)
        URLProtocol.registerClass(ToolbarFixtureProtocol.self)
    }

    var body: some Scene {
        WindowGroup {
            if CommandLine.arguments.contains(where: { $0.hasPrefix("editor") }) {
                CatalogEditorHub(bookID: 10, currentEditionID: 20, onSaved: {})
            } else if CommandLine.arguments.contains(where: { $0.hasPrefix("edition") }) {
                NavigationStack {
                    CatalogEditionLoader(id: 20, bookID: 10, service: .live(), onSaved: {})
                }
            } else { ToolbarFixtureView() }
        }
    }
}

private struct ToolbarFixtureView: View {
    @AppStorage(ToolbarFixtureProtocol.requestCountKey) private var requests = 0
    @State private var book = BookProgress(id: "fixture", title: "Toolbar regression test", author: "Example author", bookId: 10, originalTitle: "Toolbar regression test")

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Permission requests: \(requests)")
                Text(CommandLine.arguments.contains("denied") ? "Expected: no pencil" : CommandLine.arguments.contains("scope-error") ? "Expected: access error button" : "Expected: pencil at top right")
                Button("Switch fixture account") {
                    let next = UserDefaults.standard.string(forKey: "HardcoverAPIKey") == "toolbar-fixture" ? "toolbar-fixture-2" : "toolbar-fixture"
                    UserDefaults.standard.set(next, forKey: "HardcoverAPIKey")
                }
            }
            .padding()
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { } }
            }
            .catalogEditing(book: $book) { _ in }
        }
        .task {
            if CommandLine.arguments.contains("switch-account") {
                try? await Task.sleep(for: .seconds(1))
                UserDefaults.standard.set("toolbar-fixture-2", forKey: "HardcoverAPIKey")
            }
        }
    }
}
