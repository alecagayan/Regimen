//
//  RecommendationEngineTests.swift
//  RegimenTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Regimen

/// `RecommendationEngine` is pure and deterministic by design, so its
/// behaviour is worth pinning down directly rather than only ever being
/// observed through a scan.
struct RecommendationEngineTests {

    // MARK: - Helpers

    private func result(
        score: Double = 70,
        findings: [FindingKind: Int] = [:],
        attributes: [SkinAttribute] = []
    ) -> SkinScanResult {
        let expanded = findings.flatMap { kind, count in
            (0..<count).map { _ in SkinFinding(kind: kind, zone: .forehead, cellCount: 4) }
        }
        return SkinScanResult(
            score: score,
            findings: expanded,
            overlay: nil,
            faceRect: .zero,
            attributes: attributes
        )
    }

    private func product(
        name: String = "Test Product",
        tags: [ConflictTag],
        isArchived: Bool = false
    ) -> Product {
        Product(
            userID: UUID(),
            name: name,
            brand: "Brand",
            routineTime: .both,
            applicationOrder: 1,
            conflictTags: tags,
            sizeInML: 30,
            openedDate: .now,
            isArchived: isArchived
        )
    }

    private var veteran: SkinProfile {
        var profile = SkinProfile()
        profile.experience = .experienced
        profile.sensitivity = .notSensitive
        return profile
    }

    // MARK: - Coverage

    /// A scan that finds only blackheads used to produce an entirely empty
    /// "What to use" section -- `targetTags` had no `.blackhead` row at
    /// all, so every tag scored zero and nothing was returned.
    @Test func blackheadOnlyScanStillRecommendsSomething() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.blackhead: 3]),
            ownedProducts: [],
            profile: veteran
        )

        #expect(!recommendations.isEmpty)
        #expect(recommendations.contains { $0.tag == .exfoliatingAcid })
    }

    /// Attributes come from separate whole-face classifiers and were
    /// previously displayed but never acted on.
    @Test func attributesAloneProduceRecommendations() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [:], attributes: [.unevenSkin]),
            ownedProducts: [],
            profile: veteran
        )

        #expect(recommendations.contains { $0.tag == .niacinamide })
    }

    @Test func clearScanRecommendsNothing() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [:]),
            ownedProducts: [],
            profile: veteran
        )

        #expect(recommendations.isEmpty)
    }

    // MARK: - Ordering

    /// Ordering used to follow `FindingKind`'s declaration order, so a face
    /// covered in dark spots with a single blemish still led with the
    /// blemish answer.
    @Test func dominantFindingLeadsTheList() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.spot: 9, .blemish: 1]),
            ownedProducts: [],
            profile: veteran
        )

        #expect(recommendations.first?.tag == .vitaminCDerivative)
    }

    /// The inverse, to prove the ordering tracks the evidence rather than
    /// just happening to favour vitamin C.
    @Test func blemishHeavyScanLeadsWithBlemishAnswer() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.spot: 1, .blemish: 6]),
            ownedProducts: [],
            profile: veteran
        )

        #expect(recommendations.first?.tag == .exfoliatingAcid)
    }

    // MARK: - Profile awareness

    /// A sensitive beginner and a veteran should not be told the same
    /// thing with the same confidence.
    @Test func sensitiveProfileDemotesDemandingActives() {
        let scan = result(findings: [.spot: 6])
        var sensitive = SkinProfile()
        sensitive.sensitivity = .sensitive
        sensitive.experience = .beginner

        let forVeteran = RecommendationEngine.categoryRecommendations(
            for: scan, ownedProducts: [], profile: veteran
        )
        let forSensitive = RecommendationEngine.categoryRecommendations(
            for: scan, ownedProducts: [], profile: sensitive
        )

        let veteranPureCRank = forVeteran.firstIndex { $0.tag == .pureVitaminC }
        let sensitivePureCRank = forSensitive.firstIndex { $0.tag == .pureVitaminC }

        #expect(veteranPureCRank != nil)
        #expect(sensitivePureCRank != nil)
        // Demoted, not deleted -- it still targets the finding.
        #expect(sensitivePureCRank! > veteranPureCRank!)
        #expect(forSensitive.first { $0.tag == .pureVitaminC }?.needsGentleStart == true)
        #expect(forVeteran.first { $0.tag == .pureVitaminC }?.needsGentleStart == false)
    }

    /// The classifier noticing sensitivity counts for the same as the user
    /// reporting it -- including on the card's own "ease in" flag, so the
    /// caution it causes is always visible rather than silently reordering
    /// things for reasons the reader can't see.
    @Test func sensitivityAttributeFlagsGentleStart() {
        let plain = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.blemish: 5]),
            ownedProducts: [],
            profile: veteran
        )
        let flagged = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.blemish: 5], attributes: [.sensitivity]),
            ownedProducts: [],
            profile: veteran
        )

        #expect(plain.first { $0.tag == .exfoliatingAcid }?.needsGentleStart == false)
        #expect(flagged.first { $0.tag == .exfoliatingAcid }?.needsGentleStart == true)
    }

    /// Where the demotion genuinely changes the answer: with the evidence
    /// close, a gentle profile puts the mild all-rounder ahead of the acid.
    /// (With overwhelming evidence it deliberately doesn't -- BHA is still
    /// the right answer for a face full of blemishes, just flagged to ease
    /// into.)
    @Test func gentlenessReordersWhenEvidenceIsClose() {
        let scan = result(findings: [.blemish: 2], attributes: [.unevenSkin])
        var beginner = SkinProfile()
        beginner.experience = .beginner

        let forVeteran = RecommendationEngine.categoryRecommendations(
            for: scan, ownedProducts: [], profile: veteran
        )
        let forBeginner = RecommendationEngine.categoryRecommendations(
            for: scan, ownedProducts: [], profile: beginner
        )

        #expect(forVeteran.first?.tag == .exfoliatingAcid)
        #expect(forBeginner.first?.tag == .niacinamide)
    }

    // MARK: - Cabinet awareness

    @Test func ownedProductSurfacesOnItsCategory() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.blemish: 4]),
            ownedProducts: [product(name: "BHA Liquid", tags: [.exfoliatingAcid])],
            profile: veteran
        )

        let acid = recommendations.first { $0.tag == .exfoliatingAcid }
        #expect(acid?.ownedProductName == "BHA Liquid")
    }

    @Test func archivedProductsDoNotCountAsOwned() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.blemish: 4]),
            ownedProducts: [product(name: "Old BHA", tags: [.exfoliatingAcid], isArchived: true)],
            profile: veteran
        )

        let acid = recommendations.first { $0.tag == .exfoliatingAcid }
        #expect(acid?.ownedProductName == nil)
    }

    /// Recommending an acid to someone already using a retinoid without
    /// saying anything is how a user ends up with an irritated barrier and
    /// two products that fight each other.
    @Test func conflictWithOwnedProductIsFlagged() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.blemish: 4]),
            ownedProducts: [product(name: "Night Retinoid", tags: [.retinoid])],
            profile: veteran
        )

        let acid = recommendations.first { $0.tag == .exfoliatingAcid }
        #expect(acid?.conflictWarning != nil)
        #expect(acid?.conflictWarning?.contains("Night Retinoid") == true)
    }

    @Test func noConflictWarningWithoutAClashingProduct() {
        let recommendations = RecommendationEngine.categoryRecommendations(
            for: result(findings: [.blemish: 4]),
            ownedProducts: [product(name: "Plain Moisturizer", tags: [])],
            profile: veteran
        )

        #expect(recommendations.allSatisfy { $0.conflictWarning == nil })
    }

    // MARK: - Determinism

    @Test func sameScanProducesSameOrderEveryTime() {
        let scan = result(findings: [.blemish: 3, .spot: 3, .blackhead: 2])
        let first = RecommendationEngine.categoryRecommendations(
            for: scan, ownedProducts: [], profile: veteran
        )
        let second = RecommendationEngine.categoryRecommendations(
            for: scan, ownedProducts: [], profile: veteran
        )

        #expect(first.map(\.tag) == second.map(\.tag))
    }
}
