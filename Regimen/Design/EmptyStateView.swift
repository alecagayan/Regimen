//
//  EmptyStateView.swift
//  Regimen
//

import SwiftUI

/// A shared empty state, styled to match the rest of the app instead of
/// using the plain default `ContentUnavailableView` look.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.brand)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.emphasized(18))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
