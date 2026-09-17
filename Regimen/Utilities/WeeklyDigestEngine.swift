//
//  WeeklyDigestEngine.swift
//  Regimen
//

import Foundation

/// Rolls up the trailing 7 days into a handful of at-a-glance numbers for
/// `WeeklyDigestCard` -- adherence and streak (from `StreakCalculator`,
/// already the app's one source of truth for "was a day logged"), the skin
/// score's movement since before this week, which product got used most,
/// and which need reordering soon (`DepletionPredictor`, same threshold as
/// `ReorderView`). Purely a read over data already in `AppData` -- nothing
/// new is persisted or computed that isn't already shown elsewhere, this
/// just surfaces it as one weekly summary.
enum WeeklyDigestEngine {
    struct Digest {
        let daysLogged: Int
        let streak: Int
        let latestScore: Double?
        /// Change since the most recent score from before this week. Nil
        /// when there isn't a prior score to compare against.
        let scoreDelta: Double?
        let mostConsistentProduct: Product?
        let mostConsistentUseCount: Int
        let productsNeedingReorder: [Product]
    }

    static func build(
        products: [Product],
        usageLogs: [UsageLog],
        progressPhotos: [ProgressPhoto],
        restores: [StreakRestore] = [],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Digest {
        // Restores and products both have to go in, or this reports a
        // different streak than the Routine tab's badge does from the same
        // data -- they were genuinely disagreeing on screen (23 vs 1),
        // because a restore-bridged day and a rest day count there and
        // were invisible here.
        let streakResult = StreakCalculator.compute(
            from: usageLogs,
            restores: restores,
            products: products,
            historyLength: 7,
            calendar: calendar,
            now: now
        )
        // "Days logged" is deliberately NOT read off the streak's own
        // recentDays any more. That set now includes days bridged by a
        // restore and days with nothing scheduled, and counting either as
        // a day the user showed up would overstate adherence -- the streak
        // may forgive a day, but this number reports what actually
        // happened.
        let today = calendar.startOfDay(for: now)
        let loggedDays = StreakCalculator.loggedDays(logs: usageLogs, calendar: calendar)
        let daysLogged = (0..<7).count { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return loggedDays.contains(day)
        }

        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        let scoredPhotos = progressPhotos
            .filter { $0.skinScore != nil }
            .sorted { $0.timestamp < $1.timestamp }
        let latest = scoredPhotos.last
        let baseline = scoredPhotos.last { $0.timestamp < weekStart && $0.id != latest?.id }
            ?? scoredPhotos.first { $0.id != latest?.id }
        let scoreDelta: Double? = {
            guard let latestScore = latest?.skinScore, let baselineScore = baseline?.skinScore else { return nil }
            return latestScore - baselineScore
        }()

        let activeProducts = products.filter { !$0.isArchived }
        let weekLogs = usageLogs.filter { $0.timestamp >= weekStart }
        let useCounts = Dictionary(grouping: weekLogs, by: \.productID).mapValues(\.count)
        let topProductID = useCounts.max { $0.value < $1.value }?.key
        let mostConsistentProduct = topProductID.flatMap { id in activeProducts.first { $0.id == id } }

        let productsNeedingReorder = activeProducts
            .compactMap { product -> (Product, Int)? in
                guard let days = DepletionPredictor.predict(for: product, usageLogs: usageLogs.filter { $0.productID == product.id }).daysRemaining,
                      days <= 14
                else { return nil }
                return (product, days)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        return Digest(
            daysLogged: daysLogged,
            streak: streakResult.currentStreak,
            latestScore: latest?.skinScore,
            scoreDelta: scoreDelta,
            mostConsistentProduct: mostConsistentProduct,
            mostConsistentUseCount: topProductID.flatMap { useCounts[$0] } ?? 0,
            productsNeedingReorder: productsNeedingReorder
        )
    }
}
