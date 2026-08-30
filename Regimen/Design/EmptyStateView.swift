//
//  EmptyStateView.swift
//  Regimen
//

import SwiftUI

/// A shared empty state, styled to match the rest of the app instead of
/// using the plain default `ContentUnavailableView` look.
///
/// An empty state that only *describes* the emptiness leaves the user to
/// figure out the next step themselves (and on a fresh account, every tab is
/// empty at once) -- so each one can carry the action that fills it, right
/// where the user is already looking.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 88, height: 88)
                // Fixed size: this glyph is pinned inside a fixed 88pt
                // circle, so it must not grow with Dynamic Type.
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.brand)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.bodyText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
