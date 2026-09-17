//
//  ProgressGauge.swift
//  Regimen
//

import SwiftUI

/// A thin capsule gauge. Used for bottle-remaining in the Reorder tab, the
/// skin score, and how much of today's routine is done.
///
/// The fill animates to its new width rather than snapping. Every place
/// this appears, the number behind it is changing *because the user just
/// did something* -- checked a product off, finished a scan -- and a bar
/// that jumps to a new length shows the result without showing that it was
/// caused by the tap.
struct ProgressGauge: View {
    /// 0...1.
    let fraction: Double
    var tint: Color

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.subtleBorder)
                Capsule()
                    .fill(tint.gradient)
                    // A 4pt floor so an empty bottle still reads as a bar
                    // at zero rather than disappearing entirely.
                    .frame(width: max(geometry.size.width * clamped, 4))
            }
        }
        .frame(height: 6)
        .motion(Motion.value, value: clamped)
        .motion(Motion.value, value: tint)
        // The same information is always present as text beside the gauge
        // (days remaining, or the score), so announcing it twice adds noise.
        .accessibilityHidden(true)
    }
}

#Preview("Gauge states") {
    VStack(spacing: 24) {
        ProgressGauge(fraction: 0.0, tint: .red)
        ProgressGauge(fraction: 0.15, tint: .orange)
        ProgressGauge(fraction: 0.6, tint: .brand)
        ProgressGauge(fraction: 1.0, tint: .brand)
    }
    .padding(40)
    .background(Color.appBackground)
}
