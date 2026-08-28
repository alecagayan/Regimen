//
//  PillToggle.swift
//  Regimen
//

import SwiftUI

/// A generic animated pill switch, used for the AM/PM control and the
/// Sign In / Create Account mode switch — the system `.segmented` picker
/// style reads as a form control, which is the "basic UIKit app" look this
/// design system is trying to get away from.
struct PillToggle<Option: Hashable & CaseIterable & Identifiable>: View where Option.AllCases: RandomAccessCollection {
    @Binding var selection: Option
    let title: (Option) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Option.allCases) { option in
                Text(title(option))
                    .font(.emphasized(15))
                    .foregroundStyle(selection == option ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selection == option {
                            Capsule()
                                .fill(Color.brand.gradient)
                                .matchedGeometryEffect(id: "selectedPill", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selection = option
                        }
                    }
            }
        }
        .padding(4)
        .background(Color.subtleBorder.opacity(0.5), in: Capsule())
    }
}
