import Foundation

// Only the service namespace is supplied; its actual list methods are compiled below.
enum HardcoverService {
    struct FixtureProfile {
        let id = 1
        let image: UserImage? = nil
    }
    static func fetchUserProfile(username: String? = nil) async -> FixtureProfile? { FixtureProfile() }
}

func socialRequire(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw AppCoreCheckFailure(description: message) }
}

func socialHTML(_ props: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: ["props": props], options: [.sortedKeys])
    let attribute = String(decoding: data, as: UTF8.self)
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
    return "<div data-page=\"\(attribute)\"></div>"
}

func historyRow(_ id: Int) -> [String: Any] {
    ["id": id, "finished_at": "2026-09-01", "user_book": [
        "id": id + 100, "book_id": id + 1000, "rating": 4.5,
        "book": ["title": "Original \(id)", "contributions": [["author": ["name": "Writer"]]],
                 "image": ["url": "https://images.invalid/original.jpg"]],
        "edition": ["id": id + 2000, "title": "Edition \(id)", "image": ["url": "https://images.invalid/edition.jpg"]]
    ]]
}
