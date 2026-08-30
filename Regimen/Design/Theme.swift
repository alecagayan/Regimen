//
//  Theme.swift
//  Regimen
//
//  Central design tokens so every screen shares the same spacing, radii, and
//  color language instead of each view improvising its own numbers.
//

import SwiftUI

enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32

        /// Bottom padding for a scroll view that sits under a floating
        /// action button, so the last row can always be scrolled clear of
        /// it. Sized to the 58pt button plus its own bottom inset and a
        /// comfortable gap.
        static let floatingButtonClearance: CGFloat = 110
    }

    enum Radius {
        static let card: CGFloat = 20
        static let chip: CGFloat = 12
        static let control: CGFloat = 16
    }
}

// Color.appBackground / .cardSurface / .subtleBorder come from the asset
// catalog automatically (ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS).

extension Color {
    /// The asset catalog's AccentColor, referenced directly by name.
    /// `Color.accentColor` is supposed to resolve to the same asset, but in
    /// practice it can fall back to the system tint depending on where it's
    /// read from — referencing the generated asset symbol directly sidesteps
    /// that ambiguity.
    static let brand = Color.accent
}

/// The app's type scale.
///
/// Every one of these is built on a system *text style* (`.largeTitle`,
/// `.footnote`, ...) rather than a fixed point size, so all body copy scales
/// with the reader's Dynamic Type setting. Fixed `.system(size:)` type — what
/// this replaced — silently ignores that setting entirely, which is both an
/// accessibility failure and an App Review risk.
///
/// The one legitimate exception is a glyph pinned inside a fixed-size shape
/// (an avatar initial, an icon in a 28pt circle): those must not grow or they
/// overflow their container, so they still use `.system(size:)` locally.
///
/// Rounded throughout for headings and numerals — the "friendly" half of the
/// app's voice — and default-design for running text, which stays more legible
/// at small sizes.
extension Font {
    /// The big rounded headline every tab opens with (`ScreenHeader`).
    static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    /// Full-screen moments: onboarding pages, the paywall header.
    static let pageTitle = Font.system(.title, design: .rounded).weight(.bold)

    /// A headline number meant to be read from across the room — a skin
    /// score, days-remaining.
    static let metricLarge = Font.system(.title2, design: .rounded).weight(.bold)
    /// A secondary number sharing space with other content.
    static let metric = Font.system(.title3, design: .rounded).weight(.bold)

    /// The title of a card or a section of one.
    static let cardTitle = Font.system(.headline, design: .rounded)
    /// The title of a row inside a list of cards.
    static let rowTitle = Font.system(.callout, design: .rounded).weight(.semibold)
    /// An emphasized label on a control (buttons, pill toggles).
    static let controlLabel = Font.system(.callout, design: .rounded).weight(.semibold)

    /// Running text: descriptions, explanatory copy.
    static let bodyText = Font.system(.subheadline)
    /// The secondary line under a row title (brand, category, dates).
    static let rowSubtitle = Font.system(.footnote)
    /// Fine print: disclaimers, footnotes, helper text.
    static let caption = Font.system(.caption)
    /// An all-caps section label ("THIS WEEK", "SPOTTED").
    static let sectionLabel = Font.system(.caption2).weight(.semibold)
    /// Text inside a `StatusChip` or other compact pill.
    static let chipLabel = Font.system(.caption2, design: .rounded).weight(.semibold)
}

/// The card look used throughout the app: soft surface, hairline border, and
/// a wide, low-opacity shadow instead of a hard drop shadow — this is what
/// separates a "premium" flat surface from a plain system List row.
private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Color.subtleBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardBackground())
    }
}
