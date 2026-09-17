//
//  RegimenAppIntents.swift
//  Regimen
//

import AppIntents
import WidgetKit

/// Siri and Shortcuts entry points.
///
/// The widget extension has used App Intents since it shipped; the app
/// itself had none, so "log my evening routine" was only ever possible by
/// unlocking the phone and opening it. These run headless -- no UI, no app
/// launch -- which is the whole point for something done at a bathroom sink
/// with wet hands.
///
/// They write through the same App Group store the widget uses rather than
/// talking to Supabase: an intent can run in a process with no auth
/// session, exactly like the widget, so it records the intended state and
/// lets the app reconcile on next launch (see `WidgetDataStore` and
/// `AppData.flushPendingWidgetToggles`).
struct LogRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "Log My Routine"
    static var description = IntentDescription("Checks off everything in your morning or evening routine.")
    /// Headless: there's nothing to look at, and opening the app would
    /// defeat the point.
    static var openAppWhenRun = false

    @Parameter(title: "Routine", default: .auto)
    var routine: RoutineIntentTime

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = WidgetDataStore.read()
        let timeOfDay = routine.resolved()
        let items = timeOfDay == .am ? snapshot.amItems : snapshot.pmItems

        guard !items.isEmpty else {
            return .result(dialog: "Nothing is scheduled for your \(timeOfDay.rawValue) routine.")
        }

        let remaining = items.filter { !$0.isChecked }
        guard !remaining.isEmpty else {
            return .result(dialog: "Your \(timeOfDay.rawValue) routine is already done.")
        }

        for item in remaining {
            WidgetDataStore.recordToggle(productID: item.id.uuidString, timeOfDay: timeOfDay.rawValue, isChecked: true)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "RegimenWidget")

        let count = remaining.count
        return .result(dialog: "Logged \(count) \(count == 1 ? "product" : "products") for your \(timeOfDay.rawValue) routine.")
    }
}

/// Reads back where the routine stands, for "what's left in my routine?"
struct RoutineStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Routine Status"
    static var description = IntentDescription("Asks how much of your routine is left today.")
    static var openAppWhenRun = false

    @Parameter(title: "Routine", default: .auto)
    var routine: RoutineIntentTime

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = WidgetDataStore.read()
        let timeOfDay = routine.resolved()
        let items = timeOfDay == .am ? snapshot.amItems : snapshot.pmItems

        guard !items.isEmpty else {
            return .result(dialog: "Nothing is scheduled for your \(timeOfDay.rawValue) routine.")
        }

        let done = items.filter(\.isChecked).count
        guard done < items.count else {
            return .result(dialog: "Your \(timeOfDay.rawValue) routine is done. Streak is \(snapshot.streak) days.")
        }
        return .result(dialog: "\(done) of \(items.count) done. Next up: \(items.first { !$0.isChecked }?.name ?? "")")
    }
}

/// Which routine an intent refers to. `.auto` resolves through
/// `RoutineClock`, so Siri respects the user's own changeover hour.
enum RoutineIntentTime: String, AppEnum {
    case auto
    case morning
    case evening

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    static var caseDisplayRepresentations: [RoutineIntentTime: DisplayRepresentation] = [
        .auto: DisplayRepresentation(title: "Whichever is current"),
        .morning: DisplayRepresentation(title: "Morning"),
        .evening: DisplayRepresentation(title: "Evening"),
    ]

    func resolved(now: Date = .now) -> TimeOfDay {
        switch self {
        case .morning: .am
        case .evening: .pm
        case .auto: RoutineClock.currentTimeOfDay(now: now)
        }
    }
}

/// Phrases Siri accepts without the user setting anything up. `.applicationName`
/// is required in every phrase.
struct RegimenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogRoutineIntent(),
            phrases: [
                "Log my routine in \(.applicationName)",
                "Log my skincare in \(.applicationName)",
                "Mark my routine done in \(.applicationName)",
            ],
            shortTitle: "Log Routine",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: RoutineStatusIntent(),
            phrases: [
                "What's left in my \(.applicationName) routine",
                "Check my \(.applicationName) routine",
            ],
            shortTitle: "Routine Status",
            systemImageName: "list.bullet"
        )
    }
}
