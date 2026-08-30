//
//  PrimaryButtonStyle.swift
//  Regimen
//

import SwiftUI

/// The filled, full-width accent button used for primary actions on the
/// auth and onboarding screens.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.controlLabel)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// A softer full-width action, for a call to action that lives *inside* a
/// card. Same shape and weight as `.primary` but tinted rather than filled,
/// so it reads as the next step within its section without competing with
/// the screen's own primary button.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.controlLabel)
            .foregroundStyle(Color.brand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
