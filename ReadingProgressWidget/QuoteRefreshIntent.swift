import AppIntents
import WidgetKit

struct QuoteRefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Quote"
    static var description = IntentDescription("Get a new random quote")

    func perform() async throws -> some IntentResult {
        // WidgetKit automatically reloads the timeline after a Button(intent:)
        // completes, so no manual reloadTimelines call is needed here.
        // Calling it explicitly would cause a double-update.
        return .result()
    }
}

struct QuoteUpdateIntervalIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Update Interval"
    static var description = IntentDescription("How often to show a new quote")
    
    @Parameter(title: "Update Every", default: .fourHours)
    var updateInterval: UpdateInterval?
    
    init(updateInterval: UpdateInterval? = .fourHours) {
        self.updateInterval = updateInterval
    }
    
    init() {
        self.updateInterval = .fourHours
    }
}

enum UpdateInterval: String, AppEnum {
    case oneHour = "1 hour"
    case twoHours = "2 hours"
    case fourHours = "4 hours"
    case eightHours = "8 hours"
    case twelveHours = "12 hours"
    case oneDay = "24 hours"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Update Interval"
    
    static var caseDisplayRepresentations: [UpdateInterval: DisplayRepresentation] = [
        .oneHour: "Every hour",
        .twoHours: "Every 2 hours",
        .fourHours: "Every 4 hours",
        .eightHours: "Every 8 hours",
        .twelveHours: "Every 12 hours",
        .oneDay: "Once a day"
    ]
    
    var hours: Int {
        switch self {
        case .oneHour: return 1
        case .twoHours: return 2
        case .fourHours: return 4
        case .eightHours: return 8
        case .twelveHours: return 12
        case .oneDay: return 24
        }
    }
}
