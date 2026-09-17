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
    // Leads with the scan: it's the most distinctive thing the app does and
    // the main reason someone subscribes, and it went unmentioned here
    // entirely -- four screens of features, none of them the hook.
    OnboardingPage(
        icon: "sparkles",
        title: "Scan Your Skin",
        description: "A photo becomes a skin score, highlighted problem areas, and a plan. Analyzed entirely on your device. Your first scan is free."
    ),
    OnboardingPage(
        icon: "checklist",
        title: "Track Your Routine",
        description: "Check off products as you use them. Regimen warns you if two shouldn't be layered together."
    ),
    OnboardingPage(
        icon: "cart",
        title: "Never Run Out",
        description: "Regimen learns your usage rate and predicts when each product runs out, with a reminder a week before."
    ),
    OnboardingPage(
        icon: "camera.on.rectangle",
        title: "See Your Progress",
        description: "Compare any two photos side by side to see what's actually changed."
    ),
]

/// Shown once, immediately after account creation — gated by
/// `Profile.hasCompletedOnboarding` so it never appears again on later
/// sign-ins, including from a different device on the same account.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var pageIndex = 0
    @State private var showingCatalogPicker = false
    @State private var addingCatalogItem: CatalogProduct?
    /// Set once a product has actually been added, so the final screen can
    /// acknowledge it rather than repeating the same ask.
    @State private var hasAddedProduct = false

    private var isLastPage: Bool { pageIndex == onboardingPages.count }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pageIndex) {
                ForEach(Array(onboardingPages.enumerated()), id: \.element.id) { index, page in
                    OnboardingPageView(page: page).tag(index)
                }
                activationPage.tag(onboardingPages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageIndicator

            Button(primaryTitle) {
                if isLastPage {
                    if hasAddedProduct {
                        Analytics.track(.onboardingCompleted)
                        onFinish()
                    } else {
                        showingCatalogPicker = true
                    }
                } else {
                    withAnimation { pageIndex += 1 }
                }
            }
            .buttonStyle(.primary)
            .padding(.horizontal, Theme.Spacing.lg)

            Button(isLastPage ? "I'll do this later" : "Skip") {
                Analytics.track(.onboardingSkipped)
                onFinish()
            }
                .font(.bodyText)
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showingCatalogPicker) {
            CatalogPickerView { item in
                showingCatalogPicker = false
                addingCatalogItem = item
            }
        }
        .sheet(item: $addingCatalogItem, onDismiss: { hasAddedProduct = true }) { item in
            ProductEditView(product: nil, prefillCatalogItem: item)
        }
        .onAppear { Analytics.track(.onboardingStarted) }
    }

    private var primaryTitle: String {
        guard isLastPage else { return "Next" }
        return hasAddedProduct ? "Start Using Regimen" : "Add My First Product"
    }

    /// Onboarding used to end by dropping the user into an empty app, with
    /// a floating "+" and a ten-field form between them and anything
    /// working. Finishing *inside* catalog search instead means the first
    /// real screen they see already has something on it.
    private var activationPage: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 140, height: 140)
                Image(systemName: hasAddedProduct ? "checkmark" : "plus")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.brand)
            }
            VStack(spacing: Theme.Spacing.sm) {
                Text(hasAddedProduct ? "You're Set Up" : "Add Your First Product")
                    .font(.pageTitle)
                    .multilineTextAlignment(.center)
                Text(
                    hasAddedProduct
                        ? "Add the rest of your cabinet any time."
                        : "Search for something you already use. Brand and ingredients fill themselves in."
                )
                .font(.bodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            }
            Spacer()
            Spacer()
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0...onboardingPages.count, id: \.self) { i in
                Capsule()
                    .fill(i == pageIndex ? Color.brand : Color.subtleBorder)
                    .frame(width: i == pageIndex ? 20 : 8, height: 8)
                    .motion(Motion.toggle, value: pageIndex)
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
