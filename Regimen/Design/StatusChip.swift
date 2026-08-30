//
//  StatusChip.swift
//  Regimen
//

import SwiftUI

/// A small colored pill for a short status word (a conflict tag, "Archived",
/// a days-remaining label). Used instead of plain caption text wherever a
/// value needs to draw the eye.
struct StatusChip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.chipLabel)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
