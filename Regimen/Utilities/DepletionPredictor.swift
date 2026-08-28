//
//  DepletionPredictor.swift
//  Regimen
//

import Foundation

/// Forecasts when a product will run out from its recent usage rate.
///
/// This is deliberately a simple linear model (average mL/day, extrapolated
/// forward) rather than anything statistical/ML-based:
/// - A single user logging a single product produces very little data —
///   nowhere near enough to fit a more sophisticated model (e.g. one that
///   accounts for trend, seasonality, or day-of-week effects) without
///   overfitting noise.
/// - Skincare usage per application is fairly consistent for a given
///   product/routine, so day-to-day variance is small and a moving average
///   is already a good approximation of the "true" rate.
/// - It has to run instantly and deterministically on-device with no
///   external dependencies.
/// If usage patterns turn out to need more nuance later (e.g. detecting a
/// recent change in usage frequency), this is the one place to revisit.
enum DepletionPredictor {
    struct Result {
        let averageMLPerDay: Double?
        let predictedEmptyDate: Date?
        let daysRemaining: Int?
        /// Fraction of the bottle physically left (0...1), independent of
        /// whether there's enough recent history to project a date. Used to
        /// draw a visual gauge even before a prediction is possible.
        let remainingFraction: Double
    }

    /// - Parameters:
    ///   - usageLogs: this product's usage logs (any order, any time span —
    ///     filtering to the lookback window happens here).
    ///   - lookbackDays: how far back to sample usage logs when computing
    ///     the average daily rate. 14 days is long enough to smooth out a
    ///     skipped day here or there, short enough to react if the user's
    ///     routine has genuinely changed.
    static func predict(
        for product: Product,
        usageLogs: [UsageLog],
        lookbackDays: Int = 14,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Result {
        let totalUsedAllTime = usageLogs.reduce(0) { $0 + $1.estimatedAmountUsedML }
        let remainingML = max(product.sizeInML - totalUsedAllTime, 0)
        let remainingFraction = product.sizeInML > 0 ? min(max(remainingML / product.sizeInML, 0), 1) : 0

        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let recentLogs = usageLogs.filter { $0.timestamp >= cutoff }

        guard !recentLogs.isEmpty else {
            return Result(averageMLPerDay: nil, predictedEmptyDate: nil, daysRemaining: nil, remainingFraction: remainingFraction)
        }

        let totalRecentUsage = recentLogs.reduce(0) { $0 + $1.estimatedAmountUsedML }

        // Divide by the actual span of logged days rather than a fixed
        // `lookbackDays`, so a product opened only 3 days ago isn't diluted
        // by days before it existed.
        let earliestRecentLog = recentLogs.map(\.timestamp).min() ?? now
        let spanDays = max(calendar.dateComponents([.day], from: earliestRecentLog, to: now).day ?? 0, 1)
        let averagePerDay = totalRecentUsage / Double(spanDays)

        guard averagePerDay > 0 else {
            return Result(averageMLPerDay: 0, predictedEmptyDate: nil, daysRemaining: nil, remainingFraction: remainingFraction)
        }

        let daysRemaining = Int((remainingML / averagePerDay).rounded(.down))
        let predictedEmptyDate = calendar.date(byAdding: .day, value: daysRemaining, to: now)

        return Result(
            averageMLPerDay: averagePerDay,
            predictedEmptyDate: predictedEmptyDate,
            daysRemaining: daysRemaining,
            remainingFraction: remainingFraction
        )
    }
}
