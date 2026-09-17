//
//  ProductScheduleTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

struct ProductScheduleTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int, from anchor: Date = .now) -> Date {
        calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }

    @Test func dailyIsAlwaysScheduled() {
        let frequency = ProductFrequency.daily
        for offset in 0..<7 {
            #expect(frequency.isScheduled(on: day(offset), anchor: .now))
        }
    }

    /// Every other day, counted from the day the product was opened, so it
    /// lines up with when the user actually started rather than with an
    /// arbitrary epoch.
    @Test func everyOtherDayAlternatesFromTheOpenedDate() {
        let anchor = day(-10)
        let frequency = ProductFrequency.everyOtherDay

        #expect(frequency.isScheduled(on: anchor, anchor: anchor))
        #expect(!frequency.isScheduled(on: day(1, from: anchor), anchor: anchor))
        #expect(frequency.isScheduled(on: day(2, from: anchor), anchor: anchor))
        #expect(!frequency.isScheduled(on: day(3, from: anchor), anchor: anchor))
    }

    @Test func weekdaysMatchOnlyTheirOwnDays() {
        let target = calendar.component(.weekday, from: .now)
        let frequency = ProductFrequency.daysOfWeek([target])

        #expect(frequency.isScheduled(on: .now, anchor: .now))
        #expect(!frequency.isScheduled(on: day(1), anchor: .now))
        #expect(frequency.isScheduled(on: day(7), anchor: .now))
    }

    /// An empty weekday set would otherwise hide the product from every
    /// day forever, which is never what anyone means by "certain days".
    @Test func emptyWeekdaySetFallsBackToDaily() {
        #expect(ProductFrequency.daysOfWeek([]).isScheduled(on: .now, anchor: .now))
    }

    /// Backfilling yesterday shouldn't be blocked by interval arithmetic
    /// on a product opened after that day.
    @Test func daysBeforeTheAnchorStayScheduled() {
        let anchor = Date.now
        #expect(ProductFrequency.everyOtherDay.isScheduled(on: day(-3), anchor: anchor))
    }

    @Test func labelsReadNaturally() {
        #expect(ProductFrequency.daily.shortLabel == "Daily")
        #expect(ProductFrequency.everyOtherDay.shortLabel == "Every other day")
        #expect(ProductFrequency.everyNDays(3).shortLabel == "Every 3 days")
        #expect(ProductFrequency.daysOfWeek([2, 4, 6]).shortLabel == "3x a week")
        // A weekday set covering everything is just daily.
        #expect(ProductFrequency.daysOfWeek(Set(1...7)).isDaily)
    }

    @Test func storageRoundTrips() {
        for frequency in [ProductFrequency.daily, .everyNDays(3), .daysOfWeek([1, 3, 5])] {
            let restored = ProductFrequency(
                kind: frequency.kindKey,
                daysOfWeek: frequency.storedDaysOfWeek,
                intervalDays: frequency.storedIntervalDays
            )
            #expect(restored == frequency)
        }
    }

    // MARK: - Shelf life

    @Test func shelfLifeIsCountedFromTheOpenedDate() {
        var product = Product(
            userID: UUID(),
            name: "Vitamin C",
            brand: "Brand",
            routineTime: .am,
            applicationOrder: 1,
            sizeInML: 30,
            openedDate: day(-400),
            monthsAfterOpening: 12
        )
        #expect(product.isExpired)

        product.openedDate = day(-10)
        #expect(!product.isExpired)
        #expect(product.shelfLifeNote == nil)
    }

    @Test func noShelfLifeMeansNoClaim() {
        let product = Product(
            userID: UUID(),
            name: "Cleanser",
            brand: "Brand",
            routineTime: .both,
            applicationOrder: 1,
            sizeInML: 200,
            openedDate: day(-1000)
        )
        #expect(!product.isExpired)
        #expect(product.expiresOn == nil)
    }
}

/// A scheduled routine must not punish someone for a day with nothing due.
struct StreakRestDayTests {

    private let calendar = Calendar.current

    private func product(frequency: ProductFrequency) -> Product {
        Product(
            userID: UUID(),
            name: "Retinoid",
            brand: "Brand",
            routineTime: .pm,
            applicationOrder: 1,
            sizeInML: 30,
            openedDate: calendar.date(byAdding: .day, value: -30, to: .now) ?? .now,
            frequency: frequency
        )
    }

    private func log(for product: Product, daysAgo: Int) -> UsageLog {
        UsageLog(
            userID: product.userID,
            productID: product.id,
            timestamp: calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now,
            timeOfDay: .pm,
            estimatedAmountUsedML: 1
        )
    }

    /// The case the feature would otherwise have broken: a product used
    /// only on certain days leaves gaps that were never misses.
    @Test func daysWithNothingScheduledDoNotBreakTheStreak() {
        // Scheduled only on the weekday three days ago, so the two days
        // since are genuine rest days.
        let target = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now)
        let item = product(frequency: .daysOfWeek([target]))

        let streak = StreakCalculator.compute(
            from: [log(for: item, daysAgo: 3)],
            restores: [],
            products: [item]
        )

        #expect(streak.currentStreak >= 3)
    }

    /// A daily product still has to be logged daily.
    @Test func missedDaysOnADailyProductStillBreakTheStreak() {
        let item = product(frequency: .daily)

        let streak = StreakCalculator.compute(
            from: [log(for: item, daysAgo: 3)],
            restores: [],
            products: [item]
        )

        #expect(streak.currentStreak == 0)
    }

    /// An empty cabinet would make every day a rest day and report an
    /// infinite streak, so it has to count for nothing instead.
    @Test func noProductsMeansNoRestDayCredit() {
        #expect(StreakCalculator.compute(from: [], restores: [], products: []).currentStreak == 0)
    }

    /// Today doesn't have to be logged yet -- the day isn't over. Without
    /// this the streak would read 0 every morning until the first check-off.
    @Test func anUnloggedTodayKeepsYesterdaysStreak() {
        let item = product(frequency: .daily)
        let logs = (1...3).map { log(for: item, daysAgo: $0) }

        #expect(StreakCalculator.compute(from: logs, restores: [], products: [item]).currentStreak == 3)
    }

    /// A restore bridges its day exactly as if it had been logged, so the
    /// run continues straight through it.
    @Test func aRestoreExtendsTheRunThroughItsDay() {
        let item = product(frequency: .daily)
        let logs = (1...3).map { log(for: item, daysAgo: $0) }
        let bridged = calendar.date(byAdding: .day, value: -4, to: .now) ?? .now
        let restore = StreakRestore(userID: item.userID, restoredOn: bridged)

        #expect(StreakCalculator.compute(from: logs, restores: [restore], products: [item]).currentStreak == 4)
    }

    /// Logging for the first time today is a streak of one, not zero.
    @Test func aSingleLogTodayCountsAsOne() {
        let item = product(frequency: .daily)

        #expect(StreakCalculator.compute(from: [log(for: item, daysAgo: 0)], restores: [], products: [item]).currentStreak == 1)
    }

    /// Two full days without a log is over, restore or not -- a restore only
    /// ever bridges one day.
    @Test func twoMissedDaysEndTheStreak() {
        let item = product(frequency: .daily)
        let logs = [log(for: item, daysAgo: 3), log(for: item, daysAgo: 4)]

        #expect(StreakCalculator.compute(from: logs, restores: [], products: [item]).currentStreak == 0)
    }
}

/// The AM/PM changeover has to be the user's, not midday's.
///
/// The hour is passed in rather than written to the shared App Group first.
/// These tests run in parallel, and an earlier version that set the stored
/// value stomped on its own siblings' state mid-run.
struct RoutineClockTests {

    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }

    @Test func middayIsTheDefaultBoundary() {
        let hour = RoutineClock.defaultChangeoverHour
        #expect(RoutineClock.currentTimeOfDay(now: date(hour: 9), changeoverHour: hour) == .am)
        #expect(RoutineClock.currentTimeOfDay(now: date(hour: 15), changeoverHour: hour) == .pm)
    }

    /// Someone whose day starts at 7pm should get their morning routine at
    /// 6pm, not their evening one.
    @Test func nightShiftChangeoverMovesTheBoundary() {
        #expect(RoutineClock.currentTimeOfDay(now: date(hour: 9), changeoverHour: 19) == .am)
        #expect(RoutineClock.currentTimeOfDay(now: date(hour: 18), changeoverHour: 19) == .am)
        #expect(RoutineClock.currentTimeOfDay(now: date(hour: 20), changeoverHour: 19) == .pm)
    }

    @Test func changeoverIsClampedToARealHour() {
        #expect(RoutineClock.clamped(hour: 99) == 23)
        #expect(RoutineClock.clamped(hour: -5) == 0)
        #expect(RoutineClock.clamped(hour: 7) == 7)
    }

    /// The next flip is today's if it hasn't happened, tomorrow's if it has.
    @Test func nextChangeoverLandsOnTheRightDay() {
        let morning = date(hour: 9)
        let next = RoutineClock.nextChangeover(after: morning, changeoverHour: 12)
        #expect(next > morning)
        #expect(Calendar.current.isDate(next, inSameDayAs: morning))

        let evening = date(hour: 20)
        let tomorrow = RoutineClock.nextChangeover(after: evening, changeoverHour: 12)
        #expect(!Calendar.current.isDate(tomorrow, inSameDayAs: evening))
    }
}

/// Flags are observations off an ingredient list, so the matching has to be
/// exact enough not to cry wolf.
struct IngredientInsightsTests {

    @Test func fragranceIsFlagged() {
        let flags = IngredientInsights.flags(for: ["Aqua", "Glycerin", "Parfum"])
        #expect(flags.contains { $0.kind == .fragrance })
    }

    /// The trap this codebase has hit before: "alcohol" is a substring of
    /// "cetearyl alcohol", an emollient that is close to the opposite of
    /// the drying solvent being flagged.
    @Test func fattyAlcoholsAreNotFlaggedAsDrying() {
        let flags = IngredientInsights.flags(for: ["Aqua", "Cetearyl Alcohol", "Glycerin"])
        #expect(!flags.contains { $0.kind == .dryingAlcohol })
    }

    @Test func denaturedAlcoholIsFlagged() {
        let flags = IngredientInsights.flags(for: ["Aqua", "Alcohol Denat."])
        #expect(flags.contains { $0.kind == .dryingAlcohol })
    }

    @Test func retinoidsRaiseAPregnancyCaution() {
        let flags = IngredientInsights.flags(for: ["Aqua", "Retinol"])
        #expect(flags.contains { $0.kind == .pregnancyCaution })
    }

    @Test func aPlainListFlagsNothing() {
        #expect(IngredientInsights.flags(for: ["Aqua", "Glycerin", "Niacinamide"]).isEmpty)
    }

    @Test func noIngredientsFlagsNothing() {
        #expect(IngredientInsights.flags(for: []).isEmpty)
    }
}
