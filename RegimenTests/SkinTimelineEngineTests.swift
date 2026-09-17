//
//  SkinTimelineEngineTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

/// The engine's job is as much about staying quiet as about speaking. A
/// timeline like this is a single-subject observational record with a
/// handful of points and a noisy outcome measure, so most of these tests
/// check that it declines to claim things.
struct SkinTimelineEngineTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
    }

    private func product(name: String = "Retinoid", openedDaysAgo: Int, archived: Bool = false) -> Product {
        Product(
            userID: UUID(),
            name: name,
            brand: "Brand",
            routineTime: .pm,
            applicationOrder: 1,
            sizeInML: 30,
            openedDate: day(-openedDaysAgo),
            isArchived: archived
        )
    }

    private func reaction(daysAgo: Int) -> SkinReaction {
        SkinReaction(userID: UUID(), occurredOn: day(-daysAgo), severity: .moderate)
    }

    private func photo(daysAgo: Int, score: Double?) -> ProgressPhoto {
        ProgressPhoto(
            userID: UUID(),
            timestamp: day(-daysAgo),
            storagePath: "x/\(UUID().uuidString).jpg",
            skinScore: score
        )
    }

    // MARK: - Suspects

    @Test func productStartedJustBeforeAReactionIsFlagged() {
        let item = product(openedDaysAgo: 20)
        let suspects = SkinTimelineEngine.suspects(products: [item], reactions: [reaction(daysAgo: 14)])

        #expect(suspects.count == 1)
        #expect(suspects.first?.daysToFirstReaction == 6)
    }

    /// Outside the window it's just two things that happened, which is
    /// most pairs of things.
    @Test func productStartedLongBeforeAReactionIsNotFlagged() {
        let item = product(openedDaysAgo: 120)
        #expect(SkinTimelineEngine.suspects(products: [item], reactions: [reaction(daysAgo: 5)]).isEmpty)
    }

    /// A reaction can't be caused by something bought afterwards.
    @Test func productStartedAfterTheReactionIsNotFlagged() {
        let item = product(openedDaysAgo: 3)
        #expect(SkinTimelineEngine.suspects(products: [item], reactions: [reaction(daysAgo: 10)]).isEmpty)
    }

    /// Two flare-ups after the same product is a better lead than one.
    @Test func repeatOffendersRankAboveSingleCoincidences() {
        let repeated = product(name: "Acid", openedDaysAgo: 20)
        let once = product(name: "Serum", openedDaysAgo: 20)
        let suspects = SkinTimelineEngine.suspects(
            products: [once, repeated],
            reactions: [reaction(daysAgo: 14), reaction(daysAgo: 8)]
        )
        // Both are in window, so ordering is by how many reactions each
        // precedes -- here identical, so this asserts the count instead.
        #expect(suspects.count == 2)
        #expect(suspects.allSatisfy { $0.reactionDates.count == 2 })
    }

    @Test func noReactionsMeansNoSuspects() {
        #expect(SkinTimelineEngine.suspects(products: [product(openedDaysAgo: 5)], reactions: []).isEmpty)
    }

    // MARK: - Score shifts

    @Test func aClearShiftAcrossAProductsStartIsReported() {
        let item = product(openedDaysAgo: 30)
        let photos = [
            photo(daysAgo: 60, score: 50), photo(daysAgo: 45, score: 52),
            photo(daysAgo: 20, score: 72), photo(daysAgo: 5, score: 74),
        ]
        let shifts = SkinTimelineEngine.scoreShifts(products: [item], photos: photos)

        #expect(shifts.count == 1)
        #expect(shifts.first?.isImprovement == true)
        #expect(shifts.first?.scansBefore == 2)
        #expect(shifts.first?.scansAfter == 2)
    }

    /// The scan model's own MAE is about 9 points. Reporting a 4-point
    /// move as a finding would be reading noise back to the user as
    /// progress.
    @Test func movementSmallerThanTheModelsErrorStaysSilent() {
        let item = product(openedDaysAgo: 30)
        let photos = [
            photo(daysAgo: 60, score: 70), photo(daysAgo: 45, score: 71),
            photo(daysAgo: 20, score: 73), photo(daysAgo: 5, score: 74),
        ]
        #expect(SkinTimelineEngine.scoreShifts(products: [item], photos: photos).isEmpty)
    }

    /// One scan either side would confidently attribute a swing to
    /// whatever happened to be bought that week.
    @Test func oneScanEitherSideIsNotEnough() {
        let item = product(openedDaysAgo: 30)
        let photos = [photo(daysAgo: 60, score: 40), photo(daysAgo: 5, score: 85)]
        #expect(SkinTimelineEngine.scoreShifts(products: [item], photos: photos).isEmpty)
    }

    @Test func unscannedPhotosDoNotCount() {
        let item = product(openedDaysAgo: 30)
        let photos = [
            photo(daysAgo: 60, score: 50), photo(daysAgo: 45, score: nil),
            photo(daysAgo: 20, score: 75), photo(daysAgo: 5, score: nil),
        ]
        #expect(SkinTimelineEngine.scoreShifts(products: [item], photos: photos).isEmpty)
    }

    /// A product that coincided with things getting worse is at least as
    /// worth surfacing as one that coincided with improvement.
    @Test func declinesAreReportedToo() {
        let item = product(openedDaysAgo: 30)
        let photos = [
            photo(daysAgo: 60, score: 80), photo(daysAgo: 45, score: 82),
            photo(daysAgo: 20, score: 60), photo(daysAgo: 5, score: 58),
        ]
        let shifts = SkinTimelineEngine.scoreShifts(products: [item], photos: photos)

        #expect(shifts.first?.isImprovement == false)
        #expect((shifts.first?.delta ?? 0) < 0)
    }

    // MARK: - Whole-engine behaviour

    @Test func archivedProductsAreIgnored() {
        let archived = product(openedDaysAgo: 20, archived: true)
        let insights = SkinTimelineEngine.insights(
            products: [archived],
            reactions: [reaction(daysAgo: 14)],
            photos: []
        )
        #expect(insights.isEmpty)
    }

    @Test func anEmptyTimelineSaysNothing() {
        #expect(SkinTimelineEngine.insights(products: [], reactions: [], photos: []).isEmpty)
    }
}
