//
//  OnboardingView.swift
//  Regimen
//

import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        icon: "checklist",
        title: "Track Your Routine",
        description: "Check off AM and PM products as you use them. We'll warn you if two products shouldn't be layered together."
    ),
    OnboardingPage(
        icon: "cart",
        title: "Never Run Out",
        description: "Regimen learns your usage rate and predicts when each product will run dry — with a reminder about a week before."
    ),
    OnboardingPage(
        icon: "camera.on.rectangle",
        title: "See Your Progress",
        description: "Build a photo timeline and compare any two photos side-by-side with a drag-to-reveal slider."
    ),
    OnboardingPage(
        icon: "cross.case.fill",
        title: "Stock Your Cabinet",
        description: "Add every product you own to your Cabinet, set when you use it, and archive the ones you're not using right now."
    ),
]

/// Shown once, immediately after account creation — gated by
/// `Profile.hasCompletedOnboarding` so it never appears again on later
/// sign-ins, including from a different device on the same account.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var pageIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pageIndex) {
                ForEach(Array(onboardingPages.enumerated()), id: \.element.id) { index, page in
                    OnboardingPageView(page: page).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageIndicator

            Button(pageIndex == onboardingPages.count - 1 ? "Get Started" : "Next") {
                if pageIndex == onboardingPages.count - 1 {
                    onFinish()
                } else {
                    withAnimation { pageIndex += 1 }
                }
            }
            .buttonStyle(.primary)
            .padding(.horizontal, Theme.Spacing.lg)

            Button("Skip", action: onFinish)
                .font(.bodyText)
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.lg)
                .opacity(pageIndex == onboardingPages.count - 1 ? 0 : 1)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(onboardingPages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == pageIndex ? Color.brand : Color.subtleBorder)
                    .frame(width: i == pageIndex ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pageIndex)
            }
        }
        .padding(.vertical, Theme.Spacing.md)
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            ZStack {
                Circle().fill(Color.brand.opacity(0.12)).frame(width: 140, height: 140)
                Image(systemName: page.icon)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.brand)
            }
            VStack(spacing: Theme.Spacing.sm) {
                Text(page.title)
                    .font(.pageTitle)
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.bodyText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            Spacer()
            Spacer()
        }
    }
}
