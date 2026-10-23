import ActivityKit
import SwiftUI
import WidgetKit

struct ReadingProgressWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingSessionActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "book.fill")
                    .font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    HStack(spacing: 8) {
                        sessionTimer(context.state).font(.title3.weight(.semibold)).monospacedDigit()
                        Text(context.state.isPaused ? "Paused" : "Reading")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                progressLabel(context)
            }
            .padding(.horizontal, 4)
            .activityBackgroundTint(Color(.secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(sessionURL(context.attributes.bookID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Reading", systemImage: "book.fill").font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    sessionTimer(context.state).font(.caption.weight(.semibold)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.title).font(.headline).lineLimit(1)
                            if !context.attributes.author.isEmpty {
                                Text(context.attributes.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        progressLabel(context)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "book.fill")
            } compactTrailing: {
                sessionTimer(context.state).font(.caption2).monospacedDigit()
            } minimal: {
                Image(systemName: "book.fill")
            }
            .widgetURL(sessionURL(context.attributes.bookID))
            .keylineTint(.accentColor)
        }
    }

    @ViewBuilder private func sessionTimer(_ state: ReadingSessionActivityAttributes.ContentState) -> some View {
        if let resumedAt = state.resumedAt, !state.isPaused {
            let start = resumedAt.addingTimeInterval(TimeInterval(-state.accumulatedSeconds))
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        } else {
            Text(Self.duration(state.accumulatedSeconds))
        }
    }

    private func progressLabel(_ context: ActivityViewContext<ReadingSessionActivityAttributes>) -> some View {
        Group {
            if context.attributes.isAudiobook {
                Text(Self.minutes(context.state.currentUnits))
            } else {
                Text("p. \(context.state.currentUnits)")
            }
        }
        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }

    private func sessionURL(_ bookID: Int) -> URL? {
        URL(string: "softcover://session?bookId=\(bookID)")
    }

    private static func duration(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", max(0, seconds) / 3600,
               (max(0, seconds) / 60) % 60, max(0, seconds) % 60)
    }

    private static func minutes(_ value: Int) -> String {
        String(format: "%dh %02dm", max(0, value) / 60, max(0, value) % 60)
    }
}
