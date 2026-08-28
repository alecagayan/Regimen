//
//  ProgressGauge.swift
//  Regimen
//

import SwiftUI

/// A thin capsule gauge showing fraction of bottle remaining. Used in the
/// Reorder tab so urgency reads visually at a glance, not just as a number.
struct ProgressGauge: View {
    /// 0...1, fraction of the bottle left.
    let fraction: Double
    var tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.subtleBorder)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(geometry.size.width * min(max(fraction, 0), 1), 4))
            }
        }
        .frame(height: 6)
    }
}
