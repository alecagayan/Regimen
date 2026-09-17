//
//  SkinTimelineEngine.swift
//  Regimen
//

import Foundation

/// Joins the three things the app already records but never read together:
/// when a product was started, when the user's skin reacted, and how the
/// scan score moved.
///
/// Every input existed before this; none of them were ever compared. The
/// reaction log's whole premise was "spot what set it off" and the only
/// help it offered was a static list of recently-opened products, which is
/// the question restated rather than answered.
///
/// The hard part here is not the arithmetic, it's refusing to overclaim.
/// A personal skincare timeline is a single-subject observational study
/// with no control, a handful of data points, and an outcome measure whose
/// own error is large. So:
///
///   - Nothing is ever phrased as a cause. Products are "worth looking at",
///     never "responsible for".
///   - A score movement smaller than the model's own error is not a
///     finding. `SkinScanService`'s calibration reports MAE ~9 on a 0-100
///     scale, so `minimumMeaningfulScoreShift` sits at 9: below that the
///     app would be reading its own noise back to the user as progress.
///   - Anything resting on fewer than `minimumScansPerSide` scans on
///     either side stays silent rather than guessing from one photo.
///
/// Deterministic and auditable, same as `ConflictChecker` and
/// `PlanEngine` -- every line traces to a rule you can read here.
enum SkinTimelineEngine {
    /// How long after starting a product a reaction is still plausibly
    /// related to it. Three weeks covers the usual irritation and purge
    /// window without sweeping in everything the user owns.
    static let suspectWindowDays = 21

    /// Scans needed on each side of a product's start date before its
    /// score shift is worth mentioning.
    static let minimumScansPerSide = 2

    /// Below this, a score change is indistinguishable from the scan
    /// model's own error (MAE ~9, see `SkinScanService`).
    static let minimumMeaningfulScoreShift = 9.0

    /// A product started shortly before one or more reactions.
    struct Suspect: Identifiable {
        let product: Product
        /// Reactions that fell inside this product's window.
        let reactionDates: [Date]
        /// Days between starting it and the first of those reactions.
        let daysToFirstReaction: Int

        var id: UUID { product.id }

        var summary: String {
            let count = reactionDates.count
            let plural = count == 1 ? "reaction" : "reactions"
            return "\(count) \(plural) within \(suspectWindowDays) days of starting this"
        }
    }

    /// How the score moved across a product's introduction.
    struct ScoreShift: Identifiable {
        let product: Product
        let averageBefore: Double
        let averageAfter: Double
        let scansBefore: Int
        let scansAfter: Int

        var id: UUID { product.id }
        var delta: Double { averageAfter - averageBefore }
        var isImprovement: Bool { delta > 0 }

        var summary: String {
            let direction = isImprovement ? "up" : "down"
            return "Score \(direction) \(abs(Int(delta.rounded()))) since you started this"
        }
    }

    struct Insights {
        var suspects: [Suspect] = []
        var shifts: [ScoreShift] = []

        var isEmpty: Bool { suspects.isEmpty && shifts.isEmpty }
    }

    static func insights(
        products: [Product],
        reactions: [SkinReaction],
        photos: [ProgressPhoto],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Insights {
        let active = products.filter { !$0.isArchived }
        return Insights(
            suspects: suspects(products: active, reactions: reactions, calendar: calendar),
            shifts: scoreShifts(products: active, photos: photos, now: now)
        )
    }

    /// Products whose start date falls within `suspectWindowDays` before a
    /// logged reaction.
    ///
    /// Ranked by how many reactions they precede, then by how soon --
    /// something started three days before two separate flare-ups is a
    /// better lead than something started three weeks before one.
    static func suspects(
        products: [Product],
        reactions: [SkinReaction],
        calendar: Calendar = .current
    ) -> [Suspect] {
        guard !reactions.isEmpty else { return [] }

        var found: [Suspect] = []
        for product in products {
            let start = calendar.startOfDay(for: product.openedDate)
            let related = reactions
                .map { calendar.startOfDay(for: $0.occurredOn) }
                .filter { reaction in
                    guard reaction >= start else { return false }
                    let gap = calendar.dateComponents([.day], from: start, to: reaction).day ?? .max
                    return gap <= suspectWindowDays
                }
                .sorted()

            guard let first = related.first else { continue }
            found.append(
                Suspect(
                    product: product,
                    reactionDates: related,
                    daysToFirstReaction: calendar.dateComponents([.day], from: start, to: first).day ?? 0
                )
            )
        }

        return found.sorted { lhs, rhs in
            lhs.reactionDates.count == rhs.reactionDates.count
                ? lhs.daysToFirstReaction < rhs.daysToFirstReaction
                : lhs.reactionDates.count > rhs.reactionDates.count
        }
    }

    /// Mean scan score before a product was opened versus after.
    ///
    /// Reported only where there's enough either side to mean anything and
    /// the movement clears the model's own error. Both guards matter: with
    /// one scan on each side this would confidently attribute a 15-point
    /// swing to whatever the user happened to buy that week.
    static func scoreShifts(
        products: [Product],
        photos: [ProgressPhoto],
        now: Date = .now
    ) -> [ScoreShift] {
        let scored = photos.compactMap { photo -> (date: Date, score: Double)? in
            guard let score = photo.skinScore else { return nil }
            return (photo.timestamp, score)
        }
        guard scored.count >= minimumScansPerSide * 2 else { return [] }

        var shifts: [ScoreShift] = []
        for product in products {
            let before = scored.filter { $0.date < product.openedDate }
            let after = scored.filter { $0.date >= product.openedDate }
            guard before.count >= minimumScansPerSide, after.count >= minimumScansPerSide else { continue }

            let averageBefore = before.map(\.score).reduce(0, +) / Double(before.count)
            let averageAfter = after.map(\.score).reduce(0, +) / Double(after.count)
            guard abs(averageAfter - averageBefore) >= minimumMeaningfulScoreShift else { continue }

            shifts.append(
                ScoreShift(
                    product: product,
                    averageBefore: averageBefore,
                    averageAfter: averageAfter,
                    scansBefore: before.count,
                    scansAfter: after.count
                )
            )
        }

        // Largest movement first, in either direction -- a product that
        // coincided with things getting worse is at least as worth seeing
        // as one that coincided with improvement.
        return shifts.sorted { abs($0.delta) > abs($1.delta) }
    }
}
