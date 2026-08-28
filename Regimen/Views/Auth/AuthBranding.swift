//
//  AuthBranding.swift
//  Regimen
//

import SwiftUI

/// Shared header for the auth screens: an icon badge plus a title/subtitle,
/// matching the empty-state visual language used elsewhere in the app.
struct AuthBranding: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.brand)
            }
            Text(title)
                .font(.display(24))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.xl)
    }
}
