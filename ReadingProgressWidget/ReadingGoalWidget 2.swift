import WidgetKit
import SwiftUI

struct ReadingGoalEntry: TimelineEntry {
    let date: Date
    let goal: ReadingGoal?
}

struct ReadingGoalProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingGoalEntry {
        let sample = ReadingGoal(
            id: 123,
            goal: 50,
            metric: "book",
            endDate: "2025-12-31",
            progress: 34,
            startDate: "2025-01-01",
            conditions: nil,
            description: "2025 Reading Goal",
            percentComplete: 34.0 / 50.0,
            privacySettingId: 1
        )
        return ReadingGoalEntry(date: Date(), goal: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadingGoalEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            let goal = await fetchRelevantGoal()
            completion(ReadingGoalEntry(date: Date(), goal: goal))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingGoalEntry>) -> Void) {
        Task {
            let goal = await fetchRelevantGoal()
            let entry = ReadingGoalEntry(date: Date(), goal: goal)

            let next: Date
            if HardcoverConfig.apiKey.isEmpty || goal == nil {
                next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            } else {
                next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
            }
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchRelevantGoal() async -> ReadingGoal? {
        let goals = await HardcoverService.fetchReadingGoals()
        guard !goals.isEmpty else { return nil }

        // Välj “aktivt” mål om möjligt, annars det med närmast framtida slutdatum eller senaste
        let today = Date()
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"

        func parse(_ s: String) -> Date? { df.date(from: s) }

        // 1) Försök hitta ett mål där idag ∈ [start, end]
        if let active = goals.first(where: { g in
            guard let s = parse(g.startDate), let e = parse(g.endDate) else { return false }
            return (s ... e).contains(today)
        }) {
            return active
        }

        // 2) Annars ta det mål vars endDate ligger närmast i framtiden
        let future = goals
            .compactMap { g -> (ReadingGoal, Date)? in
                guard let e = parse(g.endDate) else { return nil }
                return (g, e)
            }
            .filter { $0.1 >= today }
            .sorted { $0.1 < $1.1 }
            .first?.0
        if let f = future { return f }

        // 3) Annars ta det senast avslutade (störst endDate)
        return goals.sorted { ($0.endDate, $0.id) > ($1.endDate, $1.id) }.first
    }
}

struct ReadingGoalWidgetEntryView: View {
    var entry: ReadingGoalProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let goal = entry.goal {
                switch family {
                case .systemSmall:
                    ReadingGoalSmallView(goal: goal)
                case .systemMedium:
                    ReadingGoalMediumView(goal: goal)
                default:
                    ReadingGoalMediumView(goal: goal)
                }
            } else {
                // Tomt-läge
                VStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No Reading Goal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private extension ReadingGoal {
    var localizedTitle: String {
        if let description = self.description {
            // Översätt “YYYY Reading Goal” till “Läsmål för YYYY” för svenskt språk
            if let regex = try? NSRegularExpression(pattern: "^(\\d{4}) Reading Goal$"),
               let match = regex.firstMatch(in: description, range: NSRange(location: 0, length: description.count)),
               let yearRange = Range(match.range(at: 1), in: description) {
                let year = String(description[yearRange])
                if Locale.current.language.languageCode?.identifier == "sv" {
                    return "Läsmål för \(year)"
                } else {
                    return "\(year) Reading Goal"
                }
            }
            return description
        }
        return NSLocalizedString("Reading Goal", comment: "")
    }

    var progressLabel: String {
        let unit = metric.lowercased() == "page" ? NSLocalizedString("pages", comment: "") : NSLocalizedString("books", comment: "")
        return String(format: NSLocalizedString("%lld of %lld %@", comment: ""), progress, goal, unit)
    }

    var percentageInt: Int { Int(min(1.0, max(0.0, percentComplete)) * 100) }
}

private struct ReadingGoalSmallView: View {
    let goal: ReadingGoal

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                CircularProgressView(progress: goal.percentComplete, color: Color.accentColor)
                    .frame(width: 48, height: 48)
                Text("\(goal.percentageInt)%")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
            }
            Text(goal.localizedTitle)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(goal.progressLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }
}

private struct ReadingGoalMediumView: View {
    let goal: ReadingGoal

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                CircularProgressView(progress: goal.percentComplete, color: Color.accentColor)
                    .frame(width: 64, height: 64)
                Text("\(goal.percentageInt)%")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.localizedTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(goal.progressLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)

                ProgressView(value: min(1.0, max(0.0, goal.percentComplete)))
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)

                // Ahead/behind schedule line
                if let schedule = scheduleStatus(for: goal) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(schedule.color)
                        Text(schedule.text)
                            .foregroundColor(schedule.color)
                    }
                    .font(.caption2)
                }

                HStack(spacing: 6) {
                    Text(format(date: goal.startDate))
                    Text("–")
                    Text(format(date: goal.endDate))
                    Spacer()
                    if goal.percentComplete >= 1.0 {
                        Text("🎉")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }

    private func format(date: String) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: date) {
            let out = DateFormatter()
            out.dateStyle = .medium
            out.timeStyle = .none
            return out.string(from: d)
        }
        return date
    }

    // MARK: - Ahead/Behind schedule
    private func scheduleStatus(for goal: ReadingGoal) -> (text: String, color: Color)? {
        let metric = goal.metric.lowercased()
        guard metric == "book" || metric == "page" else { return nil }

        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"

        guard let start = df.date(from: goal.startDate),
              let end = df.date(from: goal.endDate) else {
            return nil
        }

        let now = Date()
        let today = min(max(now, start), end)

        let total = max(end.timeIntervalSince(start), 1)
        let elapsed = max(min(today.timeIntervalSince(start), total), 0)
        let fraction = elapsed / total

        let expected = Int((Double(goal.goal) * fraction).rounded())
        let finished = goal.progress
        let delta = finished - expected

        let unit = metric == "page" ? NSLocalizedString("pages", comment: "") : NSLocalizedString("books", comment: "")

        if delta > 0 {
            let text = String(format: NSLocalizedString("You're %d %@ ahead of schedule.", comment: ""), delta, unit)
            return (text, .green)
        } else if delta < 0 {
            let text = String(format: NSLocalizedString("You're %d %@ behind schedule.", comment: ""), abs(delta), unit)
            return (text, .red)
        } else {
            let text = NSLocalizedString("You're right on schedule.", comment: "")
            return (text, .secondary)
        }
    }
}

struct ReadingGoalWidget: Widget {
    let kind: String = "ReadingGoalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReadingGoalProvider()) { entry in
            ReadingGoalWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Reading Goal")
        .description("Shows your current reading goal progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ReadingGoalWidget()
} timeline: {
    ReadingGoalEntry(date: .now, goal: ReadingGoal(
        id: 123,
        goal: 50,
        metric: "book",
        endDate: "2025-12-31",
        progress: 34,
        startDate: "2025-01-01",
        conditions: nil,
        description: "2025 Reading Goal",
        percentComplete: 34.0 / 50.0,
        privacySettingId: 1
    ))
}
