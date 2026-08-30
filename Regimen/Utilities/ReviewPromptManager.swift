//
//  ReviewPromptManager.swift
//  Regimen
//

import Foundation

/// Decides *whether* to ask for an App Store review. The asking itself is
/// done by the view, via SwiftUI's `\.requestReview` environment action --
/// this type only owns the judgement, so the policy lives in one place
/// instead of being spread across every screen that might want to prompt.
///
/// The policy is deliberately conservative. iOS itself caps the prompt at
/// three appearances per year and silently swallows the rest, so a request
/// spent on a lukewarm moment is genuinely gone -- there is no retry. Each
/// rule below exists to make sure the ones we do spend land on a user who
/// is demonstrably getting value:
///
/// - **Earned engagement.** Never prompt someone who just installed the app.
///   A user has to have actually logged their routine on several separate
///   days first.
/// - **One per version, and rarely.** At most one prompt per app version and
///   never twice within `minimumDaysBetweenPrompts`, so an enthusiastic user
///   isn't nagged every time they hit a milestone.
/// - **Positive moments only.** See `Moment` -- each case is a point where
///   the user has just succeeded at something, not a neutral screen visit.
///
/// Deliberately *not* wired to a "Rate this app" button: App Review rejects
/// apps that trigger the system prompt from a control, since the prompt may
/// not appear and leaves the button looking broken. A manual rate action
/// should open the App Store listing URL instead.
@MainActor
enum ReviewPromptManager {
    /// A point in the app where the user has just succeeded at something.
    enum Moment {
        /// Every product in today's AM or PM routine is now checked off.
        case routineCompleted
        /// A streak just crossed a milestone worth celebrating.
        case streakMilestone(Int)
        /// A scan came back better than the previous one.
        case skinScoreImproved(delta: Double)
    }

    /// Streak lengths that count as a milestone. Sparse and widening on
    /// purpose -- day 7 is an achievement, day 8 isn't.
    static let streakMilestones: Set<Int> = [7, 30, 100]

    /// A user must have logged on at least this many separate days before
    /// they're ever asked. Someone still deciding whether they like the app
    /// shouldn't be interrupted to rate it.
    static let minimumDaysLogged = 5

    /// Roughly two months. Long enough that a second prompt reads as "still
    /// enjoying this?" rather than nagging.
    static let minimumDaysBetweenPrompts = 60

    /// Improvement (in skin-score points) that counts as good news. Small
    /// wobbles between scans are noise -- see `SkinScanService`'s notes on
    /// the score's real-world precision -- so this is set above that floor.
    static let minimumScoreImprovement: Double = 3

    private static let lastPromptedVersionKey = "reviewPrompt.lastVersion"
    private static let lastPromptedDateKey = "reviewPrompt.lastDate"

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Whether `moment` is worth spending a review request on right now.
    ///
    /// - Parameters:
    ///   - usageLogs: every usage log for the signed-in user, used to
    ///     establish that they've actually stuck with the app.
    ///   - defaults: injectable for tests.
    static func shouldRequest(
        for moment: Moment,
        usageLogs: [UsageLog],
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Bool {
        guard isMomentWorthy(moment) else { return false }
        guard hasEarnedEngagement(usageLogs: usageLogs, calendar: calendar) else { return false }

        // One prompt per version: a user who declined on this build
        // shouldn't be asked again until there's something new to rate.
        if defaults.string(forKey: lastPromptedVersionKey) == currentVersion { return false }

        if let lastDate = defaults.object(forKey: lastPromptedDateKey) as? Date {
            let daysSince = calendar.dateComponents([.day], from: lastDate, to: now).day ?? 0
            if daysSince < minimumDaysBetweenPrompts { return false }
        }

        return true
    }

    /// Records that a prompt was just requested. Call this whenever
    /// `shouldRequest` returned true and the request was actually made --
    /// iOS may or may not have shown anything, and there's no callback to
    /// tell us which, so a request is counted as spent either way.
    static func recordRequested(defaults: UserDefaults = .standard, now: Date = .now) {
        defaults.set(currentVersion, forKey: lastPromptedVersionKey)
        defaults.set(now, forKey: lastPromptedDateKey)
    }

    private static func isMomentWorthy(_ moment: Moment) -> Bool {
        switch moment {
        case .routineCompleted:
            return true
        case .streakMilestone(let days):
            return streakMilestones.contains(days)
        case .skinScoreImproved(let delta):
            return delta >= minimumScoreImprovement
        }
    }

    private static func hasEarnedEngagement(usageLogs: [UsageLog], calendar: Calendar) -> Bool {
        let distinctDays = Set(usageLogs.map { calendar.startOfDay(for: $0.timestamp) })
        return distinctDays.count >= minimumDaysLogged
    }
}
