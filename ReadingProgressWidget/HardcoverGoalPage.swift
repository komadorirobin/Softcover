import Foundation

enum HardcoverGoalPage {
    /// A valid empty goals array is different from an unreadable page or malformed goal.
    static func decode(_ html: String) -> [ReadingGoal]? {
        guard let attribute = html.range(of: "data-page=\""),
              let end = html[attribute.upperBound...].firstIndex(of: "\"") else { return nil }
        let json = String(html[attribute.upperBound..<end])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        guard let data = json.data(using: .utf8) else { return nil }
        struct Page: Decodable {
            struct Props: Decodable { let goals: [ReadingGoal] }
            let props: Props
        }
        return (try? JSONDecoder().decode(Page.self, from: data))?.props.goals
    }
}
