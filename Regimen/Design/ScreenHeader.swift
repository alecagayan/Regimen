//
//  ScreenHeader.swift
//  Regimen
//
//  A shared large-title header used instead of the default UINavigationBar
//  title on every tab, so all four screens open with the same rhythm: a big
//  rounded headline plus a small contextual subtitle.
//

import SwiftUI

struct ScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.display(34))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.emphasized(15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
    }
}
