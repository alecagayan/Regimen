//
//  ConflictBanner.swift
//  Regimen
//

import SwiftUI

/// Shown above the checklist in `RoutineView` when `ConflictChecker` flags a
/// pairing among today's active products.
struct ConflictBanner: View {
    let conflicts: [ConflictChecker.Conflict]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(conflicts) { conflict in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(conflict.productA.name) + \(conflict.productB.name)")
                            .font(.emphasized(14))
                            .foregroundStyle(.primary)
                        Text(conflict.reason)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}
