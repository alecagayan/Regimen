//
//  WeeklyDigestEngineTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

/// The digest and the Routine tab's streak badge read the same data and
/// were reporting different numbers -- 23 against 1 on screen -- because
/// the digest dropped `restores:` and `products:` on the floor. These pin
/// the two to each other.
struct WeeklyDigestEngineTests {

    private let calendar = Calendar.current

    private func product(frequency: ProductFrequency = .daily) -> Product {
        Product(
            userID: UUID(),
            name: "Cleanser",
            brand: "Brand",
            routineTime: .both,
            applicationOrder: 1,
            sizeInML: 200,
            openedDate: calendar.date(byAdding: .day, value: -60, to: .now) ?? .now,
            frequency: frequency
        )
    }

    private func log(for product: Product, daysAgo: Int) -> UsageLog {
        UsageLog(
            userID: product.userID,
            productID: product.id,
            timestamp: calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now,
            timeOfDay: .am,
            estimatedAmountUsedML: 1
        )
    }

    /// The bug, stated directly.
    @Test func theDigestStreakMatchesTheRoutineBadge() {
        let item = product()
        let logs = (1...3).map { log(for: item, daysAgo: $0) }
        let bridged = calendar.date(byAdding: .day, value: -4, to: .now) ?? .now
        let restore = StreakRestore(userID: item.userID, restoredOn: bridged)

        let badge = StreakCalculator.compute(from: logs, restores: [restore], products: [item]).currentStreak
        let digest = WeeklyDigestEngine.build(
            products: [item],
            usageLogs: logs,
            progressPhotos: [],
            restores: [restore]
        )

        #expect(digest.streak == badge)
        #expect(digest.streak == 4)
    }

    /// Adherence has to stay honest even though the streak forgives days:
    /// a restore bridges the streak but is not a day the user showed up.
    @Test func aRestoredDayDoesNotCountAsADayLogged() {
        let item = product()
        let logs = (1...3).map { log(for: item, daysAgo: $0) }
        let bridged = calendar.date(byAdding: .day, value: -4, to: .now) ?? .now
        let restore = StreakRestore(userID: item.userID, restoredOn: bridged)

        let digest = WeeklyDigestEngine.build(
            products: [item],
            usageLogs: logs,
            progressPhotos: [],
            restores: [restore]
        )

        #expect(digest.streak == 4)
        #expect(digest.daysLogged == 3)
    }

    /// Same rule for rest days: nothing was due, so the streak survives,
    /// but no one logged anything either.
    @Test func restDaysDoNotInflateDaysLogged() {
        let weekday = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now)
        let item = product(frequency: .daysOfWeek([weekday]))
        let logs = [log(for: item, daysAgo: 1)]

        let digest = WeeklyDigestEngine.build(products: [item], usageLogs: logs, progressPhotos: [])

        #expect(digest.daysLogged == 1)
        #expect(digest.streak >= 1)
    }

    @Test func daysLoggedCountsOnlyTheLastSevenDays() {
        let item = product()
        let logs = (0...20).map { log(for: item, daysAgo: $0) }

        let digest = WeeklyDigestEngine.build(products: [item], usageLogs: logs, progressPhotos: [])

        #expect(digest.daysLogged == 7)
    }

    @Test func noLogsMeansNoStreakAndNoDays() {
        let digest = WeeklyDigestEngine.build(products: [product()], usageLogs: [], progressPhotos: [])
        #expect(digest.streak == 0)
        #expect(digest.daysLogged == 0)
    }
}
