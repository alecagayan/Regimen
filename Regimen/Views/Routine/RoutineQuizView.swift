//
//  RoutineQuizView.swift
//  Regimen
//

import SwiftUI

/// Four questions in front of the routine builder.
///
/// The scan can see what's on the surface, but not how skin *behaves* --
/// whether it stings, whether it's shiny by afternoon, whether actives are
/// old news. Those change the right routine as much as the findings do, so
/// the builder asks rather than guessing. Kept to one screen: a paginated
/// wizard for four questions is friction, not thoroughness.
struct RoutineQuizView: View {
    /// Handed the finished profile; the caller presents the built routine.
    /// Nil when the quiz is opened just to review or change the answers
    /// (from Settings), where saving is the whole point and there's nothing
    /// to present afterward.
    var onComplete: ((SkinProfile) -> Void)?

    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss
    /// Pre-filled from the account's saved answers so a repeat build is two
    /// taps -- falling back to this device's local copy, then to
    /// `SkinProfile`'s cautious defaults.
    @State private var profile: SkinProfile?

    private var answers: SkinProfile {
        profile ?? appData.effectiveSkinProfile
    }

    private var actionTitle: String {
        onComplete == nil ? "Save" : "Build My Routine"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("A few quick questions so the routine actually fits your skin.")
                        .font(.bodyText)
                        .foregroundStyle(.secondary)

                    question("How does your skin usually feel?") {
                        ForEach(SkinType.allCases) { type in
                            optionRow(
                                title: type.rawValue,
                                detail: type.detail,
                                isSelected: answers.skinType == type
                            ) { update { $0.skinType = type } }
                        }
                    }

                    question("Does your skin react easily?") {
                        ForEach(SkinSensitivity.allCases) { option in
                            optionRow(
                                title: option.rawValue,
                                detail: option == .sensitive
                                    ? "Stinging, redness, or irritation from new products"
                                    : "New products don't usually bother it",
                                isSelected: answers.sensitivity == option
                            ) { update { $0.sensitivity = option } }
                        }
                    }

                    question("How much have you used active ingredients?") {
                        ForEach(ActivesExperience.allCases) { option in
                            optionRow(
                                title: option.rawValue,
                                detail: option == .beginner
                                    ? "Little or no experience with retinoids or acids"
                                    : "Comfortable with retinoids, acids, or vitamin C",
                                isSelected: answers.experience == option
                            ) { update { $0.experience = option } }
                        }
                    }

                    question("How many steps do you want?") {
                        ForEach(RoutineLength.allCases) { length in
                            optionRow(
                                title: length.rawValue,
                                detail: length.detail,
                                isSelected: answers.routineLength == length
                            ) { update { $0.routineLength = length } }
                        }
                    }

                    Button {
                        let finished = answers
                        Analytics.track(.quizCompleted)
                        Task { await appData.saveSkinProfile(finished) }
                        if let onComplete {
                            onComplete(finished)
                        } else {
                            dismiss()
                        }
                    } label: {
                        Label(actionTitle, systemImage: onComplete == nil ? "checkmark" : "wand.and.stars")
                    }
                    .buttonStyle(.primary)

                    Text("Answers are saved to your account and only shape which products get suggested.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("About Your Skin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Edits a copy of whatever is currently showing, so the first tap
    /// seeds `profile` from the account's answers rather than from a blank
    /// struct -- otherwise answering one question would silently reset the
    /// other three to their defaults.
    private func update(_ change: (inout SkinProfile) -> Void) {
        var updated = answers
        change(&updated)
        profile = updated
    }

    private func question<Content: View>(
        _ title: String,
        @ViewBuilder options: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.cardTitle)
            VStack(spacing: Theme.Spacing.sm) {
                options()
            }
        }
    }

    private func optionRow(
        title: String,
        detail: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(Motion.toggle) { action() }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rowTitle)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.clear : Color.subtleBorder, lineWidth: 2)
                    if isSelected {
                        Circle().fill(Color.brand)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isSelected ? Color.brand.opacity(0.10) : Color.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.brand.opacity(0.5) : Color.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
