//
//  PaywallView.swift
//  Regimen
//

import StoreKit
import SwiftUI

/// Shown whenever a free account taps a premium-gated feature. "Subscribe"
/// runs a real StoreKit 2 purchase (see `SubscriptionService`) -- tested
/// locally against `Regimen.storekit` via Xcode's StoreKit Testing, and
/// talks to the live App Store once the matching products exist there.
/// Every gate gives this the same feature list regardless of which one the
/// user tapped, since the pitch is "unlock everything," not "unlock this."
struct PaywallView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    @State private var subscription = SubscriptionService.shared
    @State private var errorMessage: String?
    /// Yearly selected by default -- it's the better deal for both sides
    /// (see `yearlySavingsText`), so it's the plan a first-time glance
    /// should land on. Monthly stays one tap away, never hidden.
    @State private var selectedPlan: SubscriptionPlan = .yearly

    private let features: [(icon: String, title: String, message: String)] = [
        ("sparkles", "Full Skin Scan", "Highlighted problem areas, your skin score, and a personalized plan for every photo."),
        ("chart.line.uptrend.xyaxis", "Score Trends & Milestones", "Watch your score move over time, annotated with when you started each product."),
        ("envelope.badge", "Weekly Insight Digest", "A weekly summary of your score, streak, and most-improved area."),
        ("wand.and.stars", "Auto-Built Routine", "A complete AM/PM routine assembled from your scan results and the catalog."),
        ("square.grid.2x2", "Per-Zone Progress", "See which parts of your face are improving fastest, and which need attention."),
        ("apps.iphone", "Home Screen Widget", "Today's routine and your streak, right on your home screen."),
        ("arrow.clockwise.heart", "Streak Restores", "Missed a day? Bring your streak back — one restore every \(AppData.daysBetweenStreakRestores) days."),
    ]

    private var monthlyProduct: StoreKit.Product? { subscription.product(for: .monthly) }
    private var yearlyProduct: StoreKit.Product? { subscription.product(for: .yearly) }

    /// "Save 30%" — computed from the two real StoreKit prices (twelve
    /// months of the monthly plan vs. the yearly price) rather than a
    /// hardcoded string, so it can't quietly go stale if either price ever
    /// changes in App Store Connect without this being updated to match.
    private var yearlySavingsText: String? {
        guard let monthly = monthlyProduct?.price, let yearly = yearlyProduct?.price, monthly > 0 else { return nil }
        let annualizedMonthly = monthly * Decimal(12)
        guard annualizedMonthly > yearly else { return nil }
        // Decimal has no direct rounding-to-Int convenience -- the display
        // percentage doesn't need Decimal's exactness, just a clean round
        // number, so this is the one spot that drops to Double.
        let savings = Double(truncating: ((annualizedMonthly - yearly) / annualizedMonthly) as NSDecimalNumber)
        let percent = Int((savings * 100).rounded())
        return "Save \(percent)%"
    }

    private var priceLabel: String {
        switch selectedPlan {
        case .monthly:
            guard let monthlyProduct else { return "Subscribe" }
            return "Subscribe — \(monthlyProduct.displayPrice)/month"
        case .yearly:
            guard let yearlyProduct else { return "Subscribe" }
            return "Subscribe — \(yearlyProduct.displayPrice)/year"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.brand.gradient)
                        Text("Regimen Premium")
                            .font(.pageTitle)
                        Text("Unlock the full picture of your skin.")
                            .font(.bodyText)
                            .foregroundStyle(.secondary)
                        // Honest, not a countdown: the actual lock-in
                        // mechanism is Apple's own "keep existing
                        // subscribers at their current price" option when
                        // a subscription's price is later raised in App
                        // Store Connect -- there's no enforced deadline to
                        // promise here, just that subscribing now is what
                        // qualifies for it.
                        StatusChip(text: "🐦 EARLY BIRD PRICING", tint: .orange)
                            .padding(.top, 2)
                    }
                    .padding(.top, Theme.Spacing.lg)

                    Text("Lock in today's price for as long as you stay subscribed — it goes up as more premium features are added.")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)

                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(features, id: \.title) { feature in
                            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                                Image(systemName: feature.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.brand)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.rowTitle)
                                    Text(feature.message)
                                        .font(.rowSubtitle)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(Theme.Spacing.md)
                            .cardStyle()
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    planPicker
                        .padding(.horizontal, Theme.Spacing.lg)

                    VStack(spacing: Theme.Spacing.sm) {
                        Button(action: subscribe) {
                            if subscription.isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text(priceLabel)
                            }
                        }
                        .buttonStyle(.primary)
                        .disabled(subscription.isPurchasing)

                        Button("Restore Purchases", action: restore)
                            .font(.rowSubtitle.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .disabled(subscription.isPurchasing)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Text("Cancel anytime in Settings. Payment is charged to your Apple ID.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .task { await subscription.loadProducts() }
        }
    }

    private var planPicker: some View {
        HStack(spacing: Theme.Spacing.sm) {
            planCard(
                plan: .monthly,
                title: "Monthly",
                price: monthlyProduct?.displayPrice,
                subtitle: "billed monthly",
                badge: nil
            )
            planCard(
                plan: .yearly,
                title: "Yearly",
                price: yearlyProduct?.displayPrice,
                subtitle: "billed yearly",
                badge: yearlySavingsText
            )
        }
    }

    private func planCard(plan: SubscriptionPlan, title: String, price: String?, subtitle: String, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { selectedPlan = plan }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.rowTitle)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if let badge {
                        StatusChip(text: badge, tint: Color.brand)
                    }
                }
                Text(price ?? "—")
                    .font(.metric)
                    .foregroundStyle(isSelected ? Color.brand : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isSelected ? Color.brand.opacity(0.10) : Color.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.brand : Color.subtleBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(price ?? "price unavailable"), \(subtitle)\(badge.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func subscribe() {
        errorMessage = nil
        Task {
            do {
                let purchased = try await subscription.purchase(selectedPlan)
                guard purchased else { return }
                await appData.setPremium(true)
                dismiss()
            } catch {
                print("PaywallView.subscribe failed: \(error)")
                errorMessage = "Something went wrong — please try again."
            }
        }
    }

    private func restore() {
        errorMessage = nil
        Task {
            do {
                try await subscription.restore()
                await appData.refreshEntitlement()
                if appData.isPremium {
                    dismiss()
                } else {
                    errorMessage = "No previous purchase found for this Apple ID."
                }
            } catch {
                print("PaywallView.restore failed: \(error)")
                errorMessage = "Couldn't restore purchases — please try again."
            }
        }
    }
}
