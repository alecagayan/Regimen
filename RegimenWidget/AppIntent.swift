//
//  AppIntent.swift
//  RegimenWidget
//

import AppIntents
import WidgetKit

/// Which routine the widget shows -- configured in the widget's own "Edit
/// Widget" sheet (long-press it), not in the app.
enum RoutineTimeSelection: String, AppEnum {
    case auto = "Auto"
    case am = "AM"
    case pm = "PM"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    static var caseDisplayRepresentations: [RoutineTimeSelection: DisplayRepresentation] = [
        .auto: DisplayRepresentation(title: "Auto (AM before noon, PM after)"),
        .am: DisplayRepresentation(title: "Always show AM"),
        .pm: DisplayRepresentation(title: "Always show PM"),
    ]
}

struct RegimenWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Regimen Widget"
    static var description = IntentDescription("Choose which routine the widget shows.")

    @Parameter(title: "Show", default: .auto)
    var timeSelection: RoutineTimeSelection
}

/// Checks a routine item on or off straight from the home screen, without
/// opening the app. Runs in the widget extension's own process, which has
/// no Supabase session -- see `WidgetSharedStore.toggle` and
/// `WidgetDataStore`'s header for where the write actually goes.
struct ToggleWidgetRoutineItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Routine Item"

    @Parameter(title: "Product ID")
    var productID: String

    @Parameter(title: "Time of Day")
    var timeOfDay: String

    init() {
        productID = ""
        timeOfDay = "AM"
    }

    init(productID: String, timeOfDay: String) {
        self.productID = productID
        self.timeOfDay = timeOfDay
    }

    func perform() async throws -> some IntentResult {
        WidgetSharedStore.toggle(productID: productID, timeOfDay: timeOfDay)
        return .result()
    }
}
