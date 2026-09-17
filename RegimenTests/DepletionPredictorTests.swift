//
//  DepletionPredictorTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

/// Covers the `openedDate` boundary, which is what makes "Mark as
/// Restocked" work without deleting a single usage log.
struct DepletionPredictorTests {

    private let calendar = Calendar.current

    private func product(sizeML: Double = 100, openedDaysAgo: Int) -> Product {
        Product(
            userID: UUID(),
            name: "Cleanser",
            brand: "Brand",
            routineTime: .both,
            applicationOrder: 1,
            sizeInML: sizeML,
            typicalDoseML: 2,
            openedDate: calendar.date(byAdding: .day, value: -openedDaysAgo, to: .now) ?? .now
        )
    }

    private func logs(daysAgo: [Int], product: Product) -> [UsageLog] {
        daysAgo.map { offset in
            UsageLog(
                userID: product.userID,
                productID: product.id,
                timestamp: calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now,
                timeOfDay: .am,
                estimatedAmountUsedML: product.typicalDoseML
            )
        }
    }

    /// The bug that made a repurchase impossible to express: usage was
    /// summed over all time, so re-opening a product carried the previous
    /// bottle's consumption forward and it read as empty immediately.
    @Test func usageBeforeTheOpenedDateDoesNotCountAgainstTheBottle() {
        let item = product(sizeML: 100, openedDaysAgo: 2)
        // 40 uses from the old bottle, 2 from the new one.
        let old = logs(daysAgo: Array(repeating: 30, count: 40), product: item)
        let current = logs(daysAgo: [1, 0], product: item)

        let result = DepletionPredictor.predict(for: item, usageLogs: old + current)

        // Only the 2 recent uses (4 mL of 100) should have been consumed.
        #expect(result.remainingFraction > 0.9)
    }

    /// The same history, read as one continuous bottle, is nearly empty --
    /// this is what the old behaviour produced for everyone who had ever
    /// repurchased anything.
    @Test func usageAfterTheOpenedDateDoesCount() {
        let item = product(sizeML: 100, openedDaysAgo: 60)
        let all = logs(daysAgo: Array(repeating: 30, count: 40), product: item)

        let result = DepletionPredictor.predict(for: item, usageLogs: all)

        #expect(result.remainingFraction < 0.3)
    }

    /// Restocking is modelled purely as a new opened date, so this is the
    /// behaviour the "Restocked" button depends on.
    @Test func movingTheOpenedDateForwardRefillsTheBottle() {
        let history = logs(daysAgo: Array(repeating: 20, count: 30), product: product(openedDaysAgo: 60))

        let stale = product(sizeML: 100, openedDaysAgo: 60)
        let restocked = product(sizeML: 100, openedDaysAgo: 0)

        let before = DepletionPredictor.predict(for: stale, usageLogs: history)
        let after = DepletionPredictor.predict(for: restocked, usageLogs: history)

        #expect(before.remainingFraction < after.remainingFraction)
        #expect(after.remainingFraction == 1.0)
    }

    @Test func noUsageYetLeavesABottleFullAndUnpredicted() {
        let result = DepletionPredictor.predict(for: product(openedDaysAgo: 1), usageLogs: [])

        #expect(result.remainingFraction == 1.0)
        #expect(result.daysRemaining == nil)
    }
}

/// The app and the widget must agree on which half of the day it is.
struct TimeOfDayClockTests {

    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }

    @Test func morningIsAM() {
        #expect(TimeOfDay.currentByClock(now: date(hour: 7), changeoverHour: 12) == .am)
    }

    @Test func eveningIsPM() {
        #expect(TimeOfDay.currentByClock(now: date(hour: 22), changeoverHour: 12) == .pm)
    }

    /// The changeover hour is the boundary, matching the widget's rollover.
    @Test func theChangeoverHourFlipsToPM() {
        #expect(TimeOfDay.currentByClock(now: date(hour: 11), changeoverHour: 12) == .am)
        #expect(TimeOfDay.currentByClock(now: date(hour: 12), changeoverHour: 12) == .pm)
    }
}
