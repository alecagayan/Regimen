//
//  RegimenWidget.swift
//  RegimenWidget
//
//  Home screen widget: streak + latest skin score. Runs in a separate
//  process from the app, so it can't read `AppData` -- it reads the
//  handful of numbers `WidgetDataStore` (Regimen/Services/WidgetDataStore.swift)
//  writes into the shared App Group container on every relevant app change.
//  Keys/suite name here must match that file's write side exactly.
//

import WidgetKit
import SwiftUI

private enum SharedStore {
    static let suiteName = "group.com.alecagayan.Regimen"
    static let streakKey = "streak"
    static let latestScoreKey = "latestScore"
    static let isPremiumKey = "isPremium"

    static func read() -> (streak: Int, latestScore: Double?, isPremium: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (0, nil, false)
        }
        let streak = defaults.integer(forKey: streakKey)
        let latestScore = defaults.object(forKey: latestScoreKey) as? Double
        let isPremium = defaults.bool(forKey: isPremiumKey)
        return (streak, latestScore, isPremium)
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: .now, streak: 7, latestScore: 82, isPremium: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        // Nothing here changes on its own schedule -- it only changes when
        // the app writes new data, which triggers WidgetCenter.reloadTimelines
        // directly (see WidgetDataStore). A single never-expiring entry
        // avoids WidgetKit re-invoking this needlessly.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> SimpleEntry {
        let (streak, latestScore, isPremium) = SharedStore.read()
        return SimpleEntry(date: .now, streak: streak, latestScore: latestScore, isPremium: isPremium)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let latestScore: Double?
    let isPremium: Bool
}

/// Mirrors RoutineView.StreakBadge's tiers -- kept in sync by hand since
/// the widget extension is a separate module and can't import that type.
private func streakTier(for count: Int) -> (size: CGFloat, color: Color) {
    switch count {
    case 0: (22, .secondary)
    case 1...2: (26, .orange.opacity(0.75))
    case 3...6: (30, .orange)
    case 7...13: (34, Color(red: 1.0, green: 0.45, blue: 0.05))
    case 14...29: (38, Color(red: 1.0, green: 0.3, blue: 0.05))
    default: (42, Color(red: 1.0, green: 0.2, blue: 0.05))
    }
}

struct RegimenWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        if entry.isPremium {
            statsView
        } else {
            upsellView
        }
    }

    private var statsView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                let tier = streakTier(for: entry.streak)
                Image(systemName: "flame.fill")
                    .font(.system(size: tier.size))
                    .foregroundStyle(tier.color)
                Text("\(entry.streak)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("day streak")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            if let latestScore = entry.latestScore {
                Divider()
                VStack(spacing: 2) {
                    Text("\(Int(latestScore.rounded()))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Text("skin score")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .containerBackground(Color("WidgetBackground"), for: .widget)
    }

    private var upsellView: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("Go Premium")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("for your streak and score here")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .containerBackground(Color("WidgetBackground"), for: .widget)
    }
}

struct RegimenWidget: Widget {
    let kind: String = "RegimenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RegimenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Streak & Score")
        .description("Your current routine streak and latest skin score.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    RegimenWidget()
} timeline: {
    SimpleEntry(date: .now, streak: 0, latestScore: nil, isPremium: true)
    SimpleEntry(date: .now, streak: 7, latestScore: 82, isPremium: true)
    SimpleEntry(date: .now, streak: 30, latestScore: 91, isPremium: true)
    SimpleEntry(date: .now, streak: 7, latestScore: 82, isPremium: false)
}
