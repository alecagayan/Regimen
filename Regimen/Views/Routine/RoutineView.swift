//
//  RoutineView.swift
//  Regimen
//

import StoreKit
import SwiftUI

struct RoutineView: View {
    @Environment(AppData.self) private var appData
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.requestReview) private var requestReview

    @State private var selectedTime: TimeOfDay = .am
    @State private var showingStreakCalendar = false

    private var activeProducts: [Product] {
        let filtered = appData.products
            .filter { !$0.isArchived }
            .filter { $0.routineTime == .both || $0.routineTime.rawValue == selectedTime.rawValue }
        return LayeringAdvisor.recommendedOrder(for: filtered)
    }

    private var conflicts: [ConflictChecker.Conflict] {
        ConflictChecker.conflicts(among: activeProducts)
    }

    /// Only products actually named in a detected conflict get a tag on
    /// their row — having a conflict-prone ingredient isn't itself worth
    /// flagging if nothing it's paired with today actually interacts badly.
    private var conflictedProductIDs: Set<UUID> {
        conflicts.reduce(into: Set<UUID>()) { ids, conflict in
            ids.insert(conflict.productA.id)
            ids.insert(conflict.productB.id)
        }
    }

    private var todaySubtitle: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var streak: StreakCalculator.Result {
        StreakCalculator.compute(from: appData.usageLogs, restores: appData.streakRestores)
    }

    /// Whether every product in the currently-shown routine is checked off
    /// for today. Drives both the completion banner and the review prompt.
    private var isRoutineComplete: Bool {
        guard !activeProducts.isEmpty else { return false }
        let calendar = Calendar.current
        return activeProducts.allSatisfy { product in
            appData.usageLogs(for: product).contains {
                $0.timeOfDay == selectedTime && calendar.isDateInToday($0.timestamp)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                ScreenHeader(title: "Routine", subtitle: todaySubtitle) {
                    Button {
                        showingStreakCalendar = true
                    } label: {
                        StreakBadge(count: streak.currentStreak)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to see your streak calendar")
                }

                PillToggle(selection: $selectedTime, title: \.rawValue)
                    .padding(.horizontal, Theme.Spacing.lg)

                if !conflicts.isEmpty {
                    ConflictBanner(conflicts: conflicts)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                if activeProducts.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "Nothing on Deck for \(selectedTime.rawValue)",
                        message: "Add a product and set it to \(selectedTime.rawValue) to start your routine.",
                        actionTitle: "Add a Product",
                        action: { navigation.startAddingProduct() }
                    )
                    .padding(.top, Theme.Spacing.xl)
                    Spacer()
                } else {
                    if isRoutineComplete {
                        completionBanner
                            .padding(.horizontal, Theme.Spacing.lg)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption)
                            Text("Shown in recommended application order")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(activeProducts.enumerated()), id: \.element.id) { index, product in
                                ProductCheckRow(
                                    product: product,
                                    timeOfDay: selectedTime,
                                    stepNumber: index + 1,
                                    hasConflict: conflictedProductIDs.contains(product.id)
                                )
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isRoutineComplete)
            .onChange(of: isRoutineComplete) { _, complete in
                guard complete else { return }
                askForReview(moment: .routineCompleted)
            }
            .onChange(of: streak.currentStreak) { _, days in
                askForReview(moment: .streakMilestone(days))
            }
            .sheet(isPresented: $showingStreakCalendar) {
                StreakCalendarView()
            }
        }
    }

    private var completionBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.body)
                .foregroundStyle(Color.brand)
            Text("\(selectedTime.rawValue) routine complete — nice work.")
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Color.brand.opacity(0.10), in: Capsule())
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    /// Asks only if `ReviewPromptManager` agrees this is a moment worth
    /// spending a request on. The short delay lets the check-off animation
    /// and completion banner land first -- the prompt should feel like it
    /// follows the good news, not like it interrupts it.
    private func askForReview(moment: ReviewPromptManager.Moment) {
        guard ReviewPromptManager.shouldRequest(for: moment, usageLogs: appData.usageLogs) else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            ReviewPromptManager.recordRequested()
            requestReview()
        }
    }
}

/// Flame icon + day count, escalating in both size and heat (dim gray ->
/// pale orange -> deep red-orange, with a growing glow past a week) as the
/// streak grows -- the badge itself should communicate "how far along"
/// without reading the number. Takes a plain `count` (not a
/// StreakCalculator.Result or AppData) specifically so it can be previewed
/// at any value without needing real usage-log data -- see the #Preview
/// below to see every tier at once.
struct StreakBadge: View {
    let count: Int

    private var tier: (size: CGFloat, color: Color, glow: CGFloat) {
        switch count {
        case 0: (16, .secondary, 0)
        case 1...2: (19, .orange.opacity(0.75), 0)
        case 3...6: (23, .orange, 3)
        case 7...13: (27, Color(red: 1.0, green: 0.45, blue: 0.05), 6)
        case 14...29: (31, Color(red: 1.0, green: 0.3, blue: 0.05), 10)
        default: (36, Color(red: 1.0, green: 0.2, blue: 0.05), 14)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.system(size: tier.size))
                .foregroundStyle(tier.color)
                .shadow(color: tier.color.opacity(0.6), radius: tier.glow)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: count)
            Text("\(count)")
                .font(.rowSubtitle.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "1 day streak" : "\(count) day streak")
    }
}

#Preview("Streak tiers") {
    // Every tier boundary side by side -- open this in Xcode's canvas
    // (Editor > Canvas, or Option-Cmd-Return) to see the full escalation
    // without needing real usage-log data for any of these counts.
    HStack(alignment: .bottom, spacing: 20) {
        ForEach([0, 1, 3, 7, 14, 30, 60], id: \.self) { count in
            StreakBadge(count: count)
        }
    }
    .padding(40)
    .background(Color.appBackground)
}
