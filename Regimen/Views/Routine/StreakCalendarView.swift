//
//  StreakCalendarView.swift
//  Regimen
//

import StoreKit
import SwiftUI

/// A month calendar of the days the user logged their routine, reached by
/// tapping the streak badge. Restored days (see `StreakRestore`) are drawn
/// differently from earned ones -- a restore keeps a streak alive, but the
/// calendar shouldn't pass it off as a day the user actually showed up.
struct StreakCalendarView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    @State private var visibleMonth = Calendar.current.startOfDay(for: .now)
    @State private var showingPaywall = false
    @State private var isRestoring = false
    @State private var isPurchasingCredit = false
    @State private var purchaseErrorMessage: String?
    @State private var subscription = SubscriptionService.shared

    private var calendar: Calendar { .current }

    private var loggedDays: Set<Date> {
        StreakCalculator.loggedDays(logs: appData.usageLogs, calendar: calendar)
    }

    private var restoredDays: Set<Date> {
        Set(appData.streakRestores.map { calendar.startOfDay(for: $0.restoredOn) })
    }

    private var streak: Int {
        StreakCalculator.compute(from: appData.usageLogs, restores: appData.streakRestores, calendar: calendar).currentStreak
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    summary
                    monthCard
                    legend
                    restoreSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Your Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .task { await subscription.loadRestoreCreditProduct() }
        }
    }

    // MARK: - Sections

    private var summary: some View {
        VStack(spacing: Theme.Spacing.sm) {
            StreakBadge(count: streak)
            Text(streak == 0 ? "No active streak" : "\(streak) day\(streak == 1 ? "" : "s") in a row")
                .font(.cardTitle)
            Text("\(loggedDays.count) day\(loggedDays.count == 1 ? "" : "s") logged all time")
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private var monthCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Button { step(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Previous month")

                Spacer()
                Text(visibleMonth, format: .dateTime.month(.wide).year())
                    .font(.cardTitle)
                Spacer()

                Button { step(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Next month")
                .disabled(isCurrentMonth)
                .opacity(isCurrentMonth ? 0.3 : 1)
            }
            .foregroundStyle(Color.brand)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(monthGrid.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private func dayCell(_ day: Date) -> some View {
        let isLogged = loggedDays.contains(day)
        let isRestored = restoredDays.contains(day)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > calendar.startOfDay(for: .now)

        return ZStack {
            if isLogged {
                Circle().fill(Color.brand.gradient)
            } else if isRestored {
                Circle()
                    .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    .background(Circle().fill(Color.orange.opacity(0.15)))
            } else if isToday {
                Circle().strokeBorder(Color.brand.opacity(0.5), lineWidth: 2)
            }

            Text("\(calendar.component(.day, from: day))")
                .font(.rowSubtitle.weight(isLogged || isRestored ? .bold : .regular))
                .foregroundStyle(dayTint(isLogged: isLogged, isRestored: isRestored, isFuture: isFuture))
        }
        .frame(height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: day, isLogged: isLogged, isRestored: isRestored))
    }

    private func dayTint(isLogged: Bool, isRestored: Bool, isFuture: Bool) -> Color {
        if isLogged { return .white }
        if isRestored { return .orange }
        return isFuture ? Color.secondary.opacity(0.35) : .primary
    }

    private func accessibilityLabel(for day: Date, isLogged: Bool, isRestored: Bool) -> String {
        let date = day.formatted(.dateTime.month(.wide).day())
        if isLogged { return "\(date), logged" }
        if isRestored { return "\(date), restored" }
        return "\(date), not logged"
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.md) {
            legendItem(color: .brand, filled: true, label: "Logged")
            legendItem(color: .orange, filled: false, label: "Restored")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, filled: Bool, label: String) -> some View {
        HStack(spacing: 5) {
            Group {
                if filled {
                    Circle().fill(color)
                } else {
                    Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                }
            }
            .frame(width: 12, height: 12)
            Text(label)
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        if let day = appData.restorableDay {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.clockwise.heart")
                        .foregroundStyle(.orange)
                    Text("Streak broken on \(day.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.rowTitle)
                    Spacer(minLength: 0)
                }

                if !appData.isPremium {
                    Text("Restore that day to bring your streak back. Available with Premium.")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                    Button("Unlock Streak Restores") { showingPaywall = true }
                        .buttonStyle(.primary)
                } else if let nextAvailable = appData.nextStreakRestoreAvailableOn, appData.purchasedRestoreCredits == 0 {
                    Text("You've used your free restore recently. Your next one is available \(nextAvailable.formatted(.dateTime.month(.abbreviated).day())).")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                    Button(action: purchaseCredit) {
                        if isPurchasingCredit {
                            ProgressView().tint(.white)
                        } else {
                            Text(purchaseCreditLabel)
                        }
                    }
                    .buttonStyle(.secondary)
                    .disabled(isPurchasingCredit)
                } else {
                    Text(restoreEligibleMessage)
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                    Button(action: restore) {
                        if isRestoring {
                            ProgressView().tint(.white)
                        } else {
                            Label("Restore My Streak", systemImage: "arrow.clockwise.heart")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(isRestoring)
                }

                if let purchaseErrorMessage {
                    Text(purchaseErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .cardStyle()
        }
    }

    /// Whether the free monthly restore is what's about to be spent, or a
    /// purchased credit -- so the confirmation copy doesn't claim a free
    /// restore is available when it's actually the paid balance covering it.
    private var restoreEligibleMessage: String {
        if appData.nextStreakRestoreAvailableOn == nil {
            return "Restore that day to bring your streak back. You get one free restore every \(AppData.daysBetweenStreakRestores) days."
        }
        let credits = appData.purchasedRestoreCredits
        return "Your free restore is on cooldown, but you have \(credits) purchased \(credits == 1 ? "credit" : "credits") to use instead."
    }

    private var purchaseCreditLabel: String {
        guard let product = subscription.restoreCreditProduct else { return "Buy Extra Restore" }
        return "Buy Extra Restore — \(product.displayPrice)"
    }

    // MARK: - Actions

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            await appData.restoreStreak()
        }
    }

    private func purchaseCredit() {
        isPurchasingCredit = true
        purchaseErrorMessage = nil
        Task {
            defer { isPurchasingCredit = false }
            do {
                try await appData.purchaseStreakRestoreCredit()
            } catch {
                print("StreakCalendarView.purchaseCredit failed: \(error)")
                purchaseErrorMessage = "Something went wrong — please try again."
            }
        }
    }

    private func step(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { visibleMonth = next }
    }

    // MARK: - Calendar math

    private var isCurrentMonth: Bool {
        calendar.isDate(visibleMonth, equalTo: .now, toGranularity: .month)
    }

    /// Weekday initials starting on the calendar's own first weekday, so a
    /// Monday-first locale isn't shown a Sunday-first grid.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// The visible month's days, padded with leading nils so the first of
    /// the month lands under its correct weekday column.
    private var monthGrid: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        let days = (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start)
        }
        return Array(repeating: nil, count: leadingBlanks) + days.map { Optional($0) }
    }
}
