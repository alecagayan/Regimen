//
//  RegimenWidget.swift
//  RegimenWidget
//
//  Home screen widget: today's routine as an interactive checklist, plus
//  the streak and latest skin score. Runs in a separate process from the
//  app -- see `WidgetSharedStore` for how it gets its data, and
//  `WidgetDataStore` (app target) for how a checkbox tap finds its way
//  back to Supabase.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RegimenEntry {
        RegimenEntry(
            date: .now,
            snapshot: WidgetSharedStore.Snapshot(
                streak: 7,
                latestScore: 82,
                isPremium: true,
                amItems: [
                    WidgetRoutineItem(id: UUID(), name: "Gentle Cleanser", icon: "drop.fill", isChecked: true),
                    WidgetRoutineItem(id: UUID(), name: "Vitamin C Serum", icon: "eyedropper.halffull", isChecked: false),
                ]
            ),
            timeSelection: .auto
        )
    }

    func snapshot(for configuration: RegimenWidgetConfigurationIntent, in context: Context) async -> RegimenEntry {
        currentEntry(configuration)
    }

    func timeline(for configuration: RegimenWidgetConfigurationIntent, in context: Context) async -> Timeline<RegimenEntry> {
        // Refreshed at the noon boundary, not on a fixed interval: with
        // "Auto" selected the widget flips from the AM routine to the PM
        // one at midday, and without a scheduled reload it would keep
        // showing the morning list all afternoon. Every other change
        // (app writes, checkbox taps) calls reloadTimelines directly.
        Timeline(entries: [currentEntry(configuration)], policy: .after(nextRolloverDate()))
    }

    private func currentEntry(_ configuration: RegimenWidgetConfigurationIntent) -> RegimenEntry {
        RegimenEntry(date: .now, snapshot: WidgetSharedStore.read(), timeSelection: configuration.timeSelection)
    }

    /// The next noon or midnight, whichever comes first.
    private func nextRolloverDate() -> Date {
        let calendar = Calendar.current
        let now = Date.now
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)
        if let noon, noon > now { return noon }
        return calendar.startOfDay(for: now.addingTimeInterval(86_400))
    }
}

struct RegimenEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSharedStore.Snapshot
    let timeSelection: RoutineTimeSelection

    var items: [WidgetRoutineItem] {
        switch timeSelection {
        case .am: snapshot.amItems
        case .pm: snapshot.pmItems
        case .auto: isBeforeNoon ? snapshot.amItems : snapshot.pmItems
        }
    }

    var timeOfDay: String {
        switch timeSelection {
        case .am: "AM"
        case .pm: "PM"
        case .auto: isBeforeNoon ? "AM" : "PM"
        }
    }

    var completedCount: Int { items.filter(\.isChecked).count }
    var isComplete: Bool { !items.isEmpty && completedCount == items.count }

    private var isBeforeNoon: Bool {
        Calendar.current.component(.hour, from: date) < 12
    }
}

// MARK: - Shared pieces

/// Streak flame and day count, sitting inline. Shown on every size.
private struct StreakBadge: View {
    let count: Int

    var body: some View {
        let tier = StreakTier.forCount(count)
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: tier.size))
                .foregroundStyle(tier.color)
            Text("\(count)")
                .font(.system(size: tier.size - 3, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "1 day streak" : "\(count) day streak")
    }
}

/// The skin score as a compact tinted pill.
private struct ScorePill: View {
    let score: Double

    var body: some View {
        Text("\(Int(score.rounded()))")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .accessibilityLabel("Skin score \(Int(score.rounded()))")
    }
}

/// A slim capsule track showing how much of today's routine is done.
private struct ProgressTrack: View {
    let completed: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: max(geometry.size.width * fraction, fraction > 0 ? 4 : 0))
            }
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// One checklist row: an `AppIntent` button that toggles without opening
/// the app, plus the product name.
private struct RoutineRow: View {
    let item: WidgetRoutineItem
    let timeOfDay: String
    var compact = false

    var body: some View {
        HStack(spacing: WidgetTheme.Spacing.sm) {
            Button(intent: ToggleWidgetRoutineItemIntent(productID: item.id.uuidString, timeOfDay: timeOfDay)) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 15 : 17))
                    .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Text(item.name)
                .font(compact ? .caption2 : .caption)
                .fontWeight(.medium)
                .foregroundStyle(item.isChecked ? .secondary : .primary)
                .strikethrough(item.isChecked, color: .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.isChecked ? "Done" : "Not done")
        .accessibilityHint("Double tap to toggle")
    }
}

/// Shown in place of the checklist once every item is ticked off.
private struct AllDoneView: View {
    let timeOfDay: String
    var compact = false

    var body: some View {
        VStack(spacing: WidgetTheme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: compact ? 20 : 26))
                .foregroundStyle(Color.accentColor)
            Text("\(timeOfDay) routine done")
                .font(compact ? .caption2 : .caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyRoutineView: View {
    let timeOfDay: String
    var compact = false

    var body: some View {
        VStack(spacing: WidgetTheme.Spacing.xs) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: compact ? 18 : 22))
                .foregroundStyle(.secondary)
            Text("Nothing in your \(timeOfDay) routine")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Entry view

struct RegimenWidgetEntryView: View {
    var entry: RegimenEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if !entry.snapshot.isPremium {
                LockedView()
            } else {
                switch family {
                case .systemLarge: largeView
                case .systemMedium: mediumView
                default: smallView
                }
            }
        }
        .containerBackground(WidgetTheme.backgroundGradient, for: .widget)
    }

    /// Header shared by every size: streak on the left, score on the right.
    private var header: some View {
        HStack {
            StreakBadge(count: entry.snapshot.streak)
            Spacer(minLength: WidgetTheme.Spacing.sm)
            if let score = entry.snapshot.latestScore {
                ScorePill(score: score)
            }
        }
    }

    private var progressCaption: some View {
        HStack(spacing: 4) {
            Text("\(entry.timeOfDay) ROUTINE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if !entry.items.isEmpty {
                Text("\(entry.completedCount)/\(entry.items.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isComplete ? Color.accentColor : .secondary)
            }
        }
    }

    // Small: no room for a checklist, so it leads with progress -- the
    // number you'd actually open the app to check. Spacers above and
    // below the hero keep it optically centred instead of stranding a
    // dead gap under the header.
    private var smallView: some View {
        VStack(alignment: .leading, spacing: WidgetTheme.Spacing.sm) {
            header

            Spacer(minLength: 0)

            if entry.items.isEmpty {
                Text("Nothing in your \(entry.timeOfDay) routine")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(entry.completedCount)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(entry.isComplete ? Color.accentColor : .primary)
                        Text("of \(entry.items.count)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.isComplete ? "\(entry.timeOfDay) routine done" : "\(entry.timeOfDay) steps done")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                ProgressTrack(completed: entry.completedCount, total: entry.items.count)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(WidgetTheme.Spacing.md)
    }

    // Medium and large differ only in how many rows fit and how big the
    // type is -- sharing one body keeps them from drifting apart.
    private var mediumView: some View { checklistView(rowLimit: 4, compact: true) }

    private var largeView: some View { checklistView(rowLimit: 7, compact: false) }

    private func checklistView(rowLimit: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? WidgetTheme.Spacing.sm : WidgetTheme.Spacing.md) {
            header
            progressCaption

            if entry.items.isEmpty {
                EmptyRoutineView(timeOfDay: entry.timeOfDay, compact: compact)
            } else {
                if entry.isComplete {
                    AllDoneView(timeOfDay: entry.timeOfDay, compact: compact)
                } else {
                    VStack(spacing: compact ? WidgetTheme.Spacing.xs : WidgetTheme.Spacing.sm) {
                        ForEach(visibleItems(limit: rowLimit)) { item in
                            RoutineRow(item: item, timeOfDay: entry.timeOfDay, compact: compact)
                        }
                    }
                    if entry.items.count > rowLimit {
                        Text("+\(entry.items.count - rowLimit) more")
                            .font(.system(size: compact ? 9 : 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                // Kept outside the complete/incomplete branch on purpose:
                // dropping it once everything's ticked off left the tile
                // bottom-heavy with empty space, and a full bar is the
                // clearest possible "you're done".
                ProgressTrack(completed: entry.completedCount, total: entry.items.count)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(WidgetTheme.Spacing.lg)
    }

    /// Unchecked items first, so the ones still needing action are the
    /// ones that survive the row limit on a small tile.
    private func visibleItems(limit: Int) -> [WidgetRoutineItem] {
        let ordered = entry.items.filter { !$0.isChecked } + entry.items.filter(\.isChecked)
        return Array(ordered.prefix(limit))
    }
}

private struct LockedView: View {
    var body: some View {
        VStack(spacing: WidgetTheme.Spacing.sm) {
            Image(systemName: "crown.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor.gradient)
            Text("Regimen Premium")
                .font(.caption)
                .fontWeight(.semibold)
            Text("Check off your routine right from here")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(WidgetTheme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget

struct RegimenWidget: Widget {
    let kind = WidgetSharedStore.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: RegimenWidgetConfigurationIntent.self, provider: Provider()) { entry in
            RegimenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Routine & Streak")
        .description("Check off today's routine, and keep an eye on your streak and skin score.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

private func sampleItems(checked: Int) -> [WidgetRoutineItem] {
    let names = [
        ("Gentle Cleanser", "drop.fill"),
        ("Niacinamide 10%", "eyedropper.halffull"),
        ("Hyaluronic Acid", "circle.hexagongrid.fill"),
        ("Moisturizer", "cloud.fill"),
        ("Sunscreen SPF 50", "sun.max.fill"),
    ]
    return names.enumerated().map { index, entry in
        WidgetRoutineItem(id: UUID(), name: entry.0, icon: entry.1, isChecked: index < checked)
    }
}

private func sampleEntry(
    streak: Int = 12,
    score: Double? = 84,
    isPremium: Bool = true,
    checked: Int = 2
) -> RegimenEntry {
    RegimenEntry(
        date: .now,
        snapshot: WidgetSharedStore.Snapshot(
            streak: streak,
            latestScore: score,
            isPremium: isPremium,
            amItems: sampleItems(checked: checked)
        ),
        timeSelection: .am
    )
}

#Preview("Small", as: .systemSmall) {
    RegimenWidget()
} timeline: {
    sampleEntry(checked: 2)
    sampleEntry(streak: 30, checked: 5)
    sampleEntry(streak: 0, score: nil, isPremium: false)
}

#Preview("Medium", as: .systemMedium) {
    RegimenWidget()
} timeline: {
    sampleEntry(checked: 2)
    sampleEntry(streak: 30, checked: 5)
}

#Preview("Large", as: .systemLarge) {
    RegimenWidget()
} timeline: {
    sampleEntry(checked: 2)
}
