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

extension Font {
    /// Rounded, bold display type used for screen headers — reserved for
    /// headline-scale text so the rest of the UI still reads as a normal,
    /// legible system font rather than feeling "toy-like."
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func emphasized(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
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
