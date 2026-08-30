//
//  PremiumGate.swift
//  Regimen
//

import SwiftUI

/// Wraps a premium-only view: shown normally for a premium account. For a
/// free one, `content` isn't rendered at all -- instead a single compact
/// row names the specific feature and what it does (tap to open the
/// paywall), so a free user knows what they're missing without the locked
/// view blurring in at its full (often chart-sized) height. For gating an
/// *action* (a button that runs a premium feature) rather than a passive
/// view, check `appData.isPremium` directly at the call site and present
/// `PaywallView` instead of calling this.
struct PremiumGate<Content: View>: View {
    let isPremium: Bool
    let title: String
    let message: String
    @ViewBuilder let content: () -> Content

    @State private var showingPaywall = false

    var body: some View {
        if isPremium {
            content()
        } else {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.rowTitle)
                            .foregroundStyle(.primary)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: Theme.Spacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .cardStyle()
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }
}
