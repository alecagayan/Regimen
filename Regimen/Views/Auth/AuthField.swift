//
//  AuthField.swift
//  Regimen
//

import SwiftUI

/// A labeled text field styled to match the app's card design system,
/// standing in for the plain rows a `Form` would otherwise give the auth
/// screens.
struct AuthField: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(textContentType)
            .padding(12)
            .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Color.subtleBorder, lineWidth: 1)
            )
        }
    }
}
