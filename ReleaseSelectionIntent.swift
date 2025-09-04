import WidgetKit
import AppIntents

struct ReleaseSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Releases"
    static var description = IntentDescription("Choose which upcoming releases to display in the widget.")

    @Parameter(title: "Releases", default: [])
    var releases: [ReleaseEntity]

    init() {
        self.releases = []
    }
}

// Represents a single upcoming release (edition) that the user can select.
struct ReleaseEntity: AppEntity {
    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Release"
    static var defaultQuery = ReleaseQuery()
}

// Cache for releases to avoid repeated API calls
actor ReleaseCache {
    static let shared = ReleaseCache()

    private var cachedReleases: [ReleaseEntity]?
    private var lastFetch: Date?
    private let cacheTimeout: TimeInterval = 60 // 1 minute cache

    func getReleases() async -> [ReleaseEntity] {
        if let cached = cachedReleases,
           let lastFetch = lastFetch,
           Date().timeIntervalSince(lastFetch) < cacheTimeout {
            return cached
        }

        // Hämta upp till 30 (räcker för val + större widgets)
        let items = await HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: 30)
        let entities = items.map { ReleaseEntity(id: String($0.id), title: $0.title) }

        cachedReleases = entities
        lastFetch = Date()
        return entities
    }

    func clearCache() {
        cachedReleases = nil
        lastFetch = nil
    }
}

// The query that fetches the releases.
struct ReleaseQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ReleaseEntity] {
        let all = await ReleaseCache.shared.getReleases()

        if all.isEmpty {
            await ReleaseCache.shared.clearCache()
            let retry = await ReleaseCache.shared.getReleases()
            // Behåll ordning enligt identifiers
            let set = Set(identifiers)
            let filtered = retry.filter { set.contains($0.id) }
            return sortByIdentifiers(filtered, identifiers: identifiers)
        }

        let set = Set(identifiers)
        let filtered = all.filter { set.contains($0.id) }
        return sortByIdentifiers(filtered, identifiers: identifiers)
    }

    func suggestedEntities() async throws -> [ReleaseEntity] {
        let list = await ReleaseCache.shared.getReleases()
        if list.isEmpty {
            await ReleaseCache.shared.clearCache()
            let retry = await ReleaseCache.shared.getReleases()
            if retry.isEmpty {
                throw ReleaseQueryError.noReleasesFound
            }
            return retry
        }
        return list
    }

    func defaultResult() async -> ReleaseEntity? {
        let list = await ReleaseCache.shared.getReleases()
        return list.first
    }

    private func sortByIdentifiers(_ items: [ReleaseEntity], identifiers: [String]) -> [ReleaseEntity] {
        var order: [String: Int] = [:]
        for (i, id) in identifiers.enumerated() { order[id] = i }
        return items.sorted { (a, b) -> Bool in
            (order[a.id] ?? Int.max) < (order[b.id] ?? Int.max)
        }
    }
}

enum ReleaseQueryError: LocalizedError {
    case noReleasesFound

    var errorDescription: String? {
        switch self {
        case .noReleasesFound:
            return "No upcoming releases found. We show future editions from your Want to Read list."
        }
    }
}
