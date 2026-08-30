//
//  RegimenWidgetLiveActivity.swift
//  RegimenWidget
//
//  Created by Alec Agayan on 8/29/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RegimenWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct RegimenWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RegimenWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

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

extension RegimenWidgetAttributes {
    fileprivate static var preview: RegimenWidgetAttributes {
        RegimenWidgetAttributes(name: "World")
    }
}

extension RegimenWidgetAttributes.ContentState {
    fileprivate static var smiley: RegimenWidgetAttributes.ContentState {
        RegimenWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: RegimenWidgetAttributes.ContentState {
         RegimenWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: RegimenWidgetAttributes.preview) {
   RegimenWidgetLiveActivity()
} contentStates: {
    RegimenWidgetAttributes.ContentState.smiley
    RegimenWidgetAttributes.ContentState.starEyes
}
