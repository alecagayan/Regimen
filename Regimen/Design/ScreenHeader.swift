//
//  ScreenHeader.swift
//  Regimen
//
//  A shared large-title header used instead of the default UINavigationBar
//  title on every tab, so all four screens open with the same rhythm: a big
//  rounded headline plus a small contextual subtitle.
//

import SwiftUI

struct ScreenHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    /// Trailing content aligned to the title's own baseline area — the
    /// streak badge on Routine, the profile button on Cabinet. Owning this
    /// here (rather than each tab wrapping the header in its own HStack and
    /// guessing at matching padding) is what keeps the four tabs' headers
    /// actually identical.
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        // Centered, not top-aligned: the accessory reads as a peer of the
        // title block (sitting on the axis through the title and its
        // subtitle) rather than as something tacked onto the corner.
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.screenTitle)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.rowTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() })
    }
}
