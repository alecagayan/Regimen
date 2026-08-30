//
//  WidgetTheme.swift
//  RegimenWidget
//

import SwiftUI

/// The widget's design tokens.
///
/// Deliberately a parallel, trimmed-down copy of the app's `Theme` rather
/// than a shared file: the widget extension is a separate module, and a
/// widget's constraints are different enough that sharing wholesale would
/// be the wrong call anyway. A home screen widget has a fixed, tiny canvas
/// it can never scroll, so its spacing is tighter and its hero numerals
/// stay at fixed sizes -- they'd overflow their tile if they scaled with
/// Dynamic Type the way the app's do. Supporting text still uses text
/// styles so it does scale.
enum WidgetTheme {
    enum Spacing {
        static let xs: CGFloat = 3
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    /// The widget's own surface color, matching the app's card surface.
    static let background = Color.widgetBackground

    /// A soft top-down wash over the background, so the tile reads as a
    /// designed surface rather than a flat rectangle.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, background.opacity(0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The streak flame's size and heat at a given day count.
///
/// Mirrors `RoutineView.StreakBadge`'s tiers in the app -- kept in sync by
/// hand, since the widget extension can't import that type. The sizes are
/// smaller here: the badge sits in a corner of a widget tile, not beside a
/// full-width screen title.
struct StreakTier {
    let size: CGFloat
    let color: Color

    static func forCount(_ count: Int) -> StreakTier {
        switch count {
        case 0: StreakTier(size: 15, color: .secondary)
        case 1...2: StreakTier(size: 16, color: .orange.opacity(0.75))
        case 3...6: StreakTier(size: 17, color: .orange)
        case 7...13: StreakTier(size: 18, color: Color(red: 1.0, green: 0.45, blue: 0.05))
        case 14...29: StreakTier(size: 19, color: Color(red: 1.0, green: 0.3, blue: 0.05))
        default: StreakTier(size: 20, color: Color(red: 1.0, green: 0.2, blue: 0.05))
        }
    }
}
