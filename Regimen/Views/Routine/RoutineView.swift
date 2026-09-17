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

    /// Opens on whichever routine it actually is. Hardcoding `.am` meant
    /// an evening user tapped PM every single night -- and disagreed with
    /// the widget, which has done this rollover since it shipped.
    @State private var selectedTime: TimeOfDay = TimeOfDay.currentByClock()
    @State private var showingStreakCalendar = false
    /// Which day is being logged. Limited to today and yesterday -- see
    /// `AppData.toggleUsageLog(for:timeOfDay:on:)`.
    @State private var isLoggingYesterday = false

    private var loggingDay: Date {
        isLoggingYesterday
            ? Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
            : .now
    }

    /// Products in this routine at all, before the schedule is applied.
    private var routineProducts: [Product] {
        let filtered = appData.products
            .filter { !$0.isArchived }
            .filter { $0.routineTime == .both || $0.routineTime.rawValue == selectedTime.rawValue }
        return LayeringAdvisor.recommendedOrder(for: filtered)
    }

    /// What's actually due on the day being logged.
    private var activeProducts: [Product] {
        routineProducts.filter { $0.isScheduled(on: loggingDay) }
    }

    /// In this routine but not due today, e.g. a Mon/Wed/Fri retinoid on a
    /// Tuesday. Shown collapsed so the day's list stays short without the
    /// product seeming to have vanished.
    private var notDueToday: [Product] {
        routineProducts.filter { !$0.isScheduled(on: loggingDay) }
    }

    /// Only among products actually going on the face together today --
    /// two actives on alternating nights never meet, and flagging them
    /// would be a false alarm the schedule already solved.
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
        StreakCalculator.compute(from: appData.usageLogs, restores: appData.streakRestores, products: appData.products)
    }

    private var completedCount: Int {
        activeProducts.filter { appData.isLogged($0, timeOfDay: selectedTime, on: loggingDay) }.count
    }

    /// Whether every product in the currently-shown routine is checked off.
    /// Drives both the completion banner and the review prompt.
    private var isRoutineComplete: Bool {
        !activeProducts.isEmpty && completedCount == activeProducts.count
    }

    /// Whether yesterday's routine has anything unlogged worth offering to
    /// backfill. Only surfaced when it's actually actionable -- a permanent
    /// "log yesterday" control would just be clutter for anyone keeping up.
    private var yesterdayHasUnlogged: Bool {
        guard !isLoggingYesterday, !activeProducts.isEmpty else { return false }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        return activeProducts.contains { !appData.isLogged($0, timeOfDay: selectedTime, on: yesterday) }
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

                if isLoggingYesterday {
                    backfillBanner
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                if activeProducts.isEmpty && !notDueToday.isEmpty {
                    EmptyStateView(
                        icon: "moon.zzz",
                        title: "Rest Day",
                        message: "Nothing in your \(selectedTime.rawValue) routine is scheduled for today."
                    )
                    .padding(.top, Theme.Spacing.xl)
                    Spacer()
                } else if activeProducts.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "Nothing on Deck for \(selectedTime.rawValue)",
                        message: "Add a product set to \(selectedTime.rawValue) to start your routine.",
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
                        progressRow
                            .padding(.horizontal, Theme.Spacing.lg)
                    }

                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(activeProducts.enumerated()), id: \.element.id) { index, product in
                                ProductCheckRow(
                                    product: product,
                                    timeOfDay: selectedTime,
                                    day: loggingDay,
                                    stepNumber: index + 1,
                                    hasConflict: conflictedProductIDs.contains(product.id)
                                )
                            }

                            if !notDueToday.isEmpty {
                                notDueSection
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    // Foreground refreshes are debounced to 60s, so without
                    // this there was no way at all to force a sync.
                    .refreshable { await appData.loadAll() }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // A reminder about the evening routine should open the evening
            // routine, not whichever half the clock happens to say now.
            .onChange(of: navigation.requestedRoutineTime) { _, requested in
                guard let requested else { return }
                selectedTime = requested
                navigation.requestedRoutineTime = nil
            }
            .motion(Motion.card, value: isRoutineComplete)
            .motion(Motion.card, value: isLoggingYesterday)
            // Switching AM/PM swaps the whole list; without this the new
            // contents appear with no indication they replaced anything.
            .motion(Motion.card, value: selectedTime)
            .onChange(of: isRoutineComplete) { _, complete in
                // Completing a *backfill* isn't the same good news as
                // finishing today's routine, so it shouldn't spend a review
                // request.
                guard complete, !isLoggingYesterday else { return }
                Analytics.track(.routineCompleted(timeOfDay: selectedTime.rawValue))
                // The first completed routine is the earliest honest moment
                // to ask about notifications: the user has just done the
                // thing the reminders would remind them about, so the
                // request has visible context behind it. No-op after the
                // first ask (see NotificationManager).
                Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
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

    /// Partial progress, which the screen previously showed nothing about
    /// -- it went from an undifferentiated list straight to a completion
    /// banner, with no feedback for the four times out of five that a
    /// routine is half done.
    private var progressRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(completedCount) of \(activeProducts.count) done")
                    .font(.rowSubtitle.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .motion(Motion.toggle, value: completedCount)
                Spacer(minLength: 0)
                Button {
                    Task {
                        await appData.checkOffAll(activeProducts, timeOfDay: selectedTime, on: loggingDay)
                    }
                } label: {
                    Label("Check All", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brand)
            }

            ProgressGauge(
                fraction: Double(completedCount) / Double(max(activeProducts.count, 1)),
                tint: Color.brand
            )

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                Text("Shown in recommended application order")
                    .font(.caption)
                Spacer(minLength: 0)
                if yesterdayHasUnlogged {
                    Button("Forgot yesterday?") {
                        withAnimation { isLoggingYesterday = true }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brand)
                }
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    /// Scheduled for another day. Listed rather than hidden so a product
    /// that isn't on today's list doesn't read as missing.
    private var notDueSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("NOT DUE TODAY")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Spacing.md)

            ForEach(notDueToday) { product in
                HStack(spacing: Theme.Spacing.md) {
                    ProductAvatar(name: product.name, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(product.name)
                            .font(.rowSubtitle.weight(.medium))
                        Text(product.frequency.longLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.sm)
                .opacity(0.55)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backfillBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.body)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Logging for yesterday")
                    .font(.rowSubtitle.weight(.semibold))
                Text(loggingDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Done") {
                withAnimation { isLoggingYesterday = false }
            }
            .font(.rowSubtitle.weight(.semibold))
            .foregroundStyle(Color.brand)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var completionBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.body)
                .foregroundStyle(Color.brand)
            Text(isLoggingYesterday ? "Yesterday's \(selectedTime.rawValue) routine logged." : "\(selectedTime.rawValue) routine complete.")
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
                .motion(Motion.toggle, value: count)
            Text("\(count)")
                .font(.rowSubtitle.weight(.bold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
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
