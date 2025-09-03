//
//  ReadingProgressWidgetLiveActivity.swift
//  ReadingProgressWidget
//
//  Created by Robin Bolinsson on 2025-08-22.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ReadingProgressWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ReadingProgressWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingProgressWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ReadingProgressWidgetAttributes {
    fileprivate static var preview: ReadingProgressWidgetAttributes {
        ReadingProgressWidgetAttributes(name: "World")
    }
}

extension ReadingProgressWidgetAttributes.ContentState {
    fileprivate static var smiley: ReadingProgressWidgetAttributes.ContentState {
        ReadingProgressWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ReadingProgressWidgetAttributes.ContentState {
         ReadingProgressWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ReadingProgressWidgetAttributes.preview) {
   ReadingProgressWidgetLiveActivity()
} contentStates: {
    ReadingProgressWidgetAttributes.ContentState.smiley
    ReadingProgressWidgetAttributes.ContentState.starEyes
}
