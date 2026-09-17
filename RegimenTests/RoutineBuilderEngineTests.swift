//
//  RoutineBuilderEngineTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

/// Covers `bestCandidate`, the half of the builder that decides *which*
/// product fills a step. The previous implementation took `candidates[0]`
/// -- whatever row the catalog happened to return first -- so none of these
/// expectations would have held.
struct RoutineBuilderEngineTests {

    // MARK: - Helpers

    private func catalogProduct(
        name: String,
        description: String? = nil,
        layer: LayerCategory,
        tags: [ConflictTag] = []
    ) -> CatalogProduct {
        CatalogProduct(
            id: UUID(),
            brand: "Brand",
            name: name,
            category: nil,
            suggestedConflictTags: tags,
            layerCategory: layer,
            productDescription: description
        )
    }

    private func ownedProduct(name: String, tags: [ConflictTag]) -> Product {
        Product(
            userID: UUID(),
            name: name,
            brand: "Brand",
            routineTime: .both,
            applicationOrder: 1,
            conflictTags: tags,
            sizeInML: 30,
            openedDate: .now
        )
    }

    private func profile(
        skinType: SkinType = .normal,
        sensitivity: SkinSensitivity = .notSensitive,
        experience: ActivesExperience = .experienced
    ) -> SkinProfile {
        var profile = SkinProfile()
        profile.skinType = skinType
        profile.sensitivity = sensitivity
        profile.experience = experience
        return profile
    }

    private func pick(
        _ candidates: [CatalogProduct],
        layer: LayerCategory = .cleanser,
        profile: SkinProfile,
        treatmentTags: [ConflictTag] = [],
        owned: [Product] = []
    ) -> String? {
        RoutineBuilderEngine.bestCandidate(
            from: candidates,
            for: layer,
            profile: profile,
            treatmentTags: treatmentTags,
            ownedProducts: owned
        )?.name
    }

    // MARK: - Texture fit

    private var cleansers: [CatalogProduct] {
        [
            catalogProduct(name: "Rich Cleansing Balm", layer: .cleanser),
            catalogProduct(name: "Foaming Gel Cleanser", layer: .cleanser),
        ]
    }

    @Test func oilySkinGetsTheLighterCleanser() {
        #expect(pick(cleansers, profile: profile(skinType: .oily)) == "Foaming Gel Cleanser")
    }

    @Test func drySkinGetsTheRicherCleanser() {
        #expect(pick(cleansers, profile: profile(skinType: .dry)) == "Rich Cleansing Balm")
    }

    /// The same catalog, two different people, two different answers --
    /// which is the entire point of the rewrite.
    @Test func skinTypeActuallyChangesThePick() {
        let forOily = pick(cleansers, profile: profile(skinType: .oily))
        let forDry = pick(cleansers, profile: profile(skinType: .dry))
        #expect(forOily != forDry)
    }

    /// "oil-free" splits into the word "oil", which naive whole-word
    /// matching would read as the opposite of what the label says.
    @Test func oilFreeIsNotMistakenForAnOil() {
        let candidates = [
            catalogProduct(name: "Oil-Free Gel Moisturizer", layer: .moisturizer),
            catalogProduct(name: "Rich Butter Moisturizer", layer: .moisturizer),
        ]
        #expect(pick(candidates, layer: .moisturizer, profile: profile(skinType: .oily)) == "Oil-Free Gel Moisturizer")
    }

    @Test func descriptionCountsTowardTextureNotJustName() {
        let candidates = [
            catalogProduct(name: "Daily Moisturizer A", description: "A rich, nourishing balm for parched skin.", layer: .moisturizer),
            catalogProduct(name: "Daily Moisturizer B", description: "A lightweight gel that absorbs instantly.", layer: .moisturizer),
        ]
        #expect(pick(candidates, layer: .moisturizer, profile: profile(skinType: .dry)) == "Daily Moisturizer A")
    }

    // MARK: - Targeting

    @Test func treatmentPrefersAnActiveTheScanCallsFor() {
        let candidates = [
            catalogProduct(name: "Hydrating Serum", layer: .treatment),
            catalogProduct(name: "BHA Serum", layer: .treatment, tags: [.exfoliatingAcid]),
        ]
        let tags = RoutineBuilderEngine.preferredTreatmentTags(for: [.blemish: 3])

        #expect(pick(candidates, layer: .treatment, profile: profile(), treatmentTags: tags) == "BHA Serum")
    }

    /// Targeting should outrank texture: a treatment that addresses the
    /// finding matters more than one that merely reads as light.
    @Test func targetingOutranksTexture() {
        let candidates = [
            catalogProduct(name: "Lightweight Gel Serum", layer: .treatment),
            catalogProduct(name: "Rich BHA Cream", layer: .treatment, tags: [.exfoliatingAcid]),
        ]
        let tags = RoutineBuilderEngine.preferredTreatmentTags(for: [.blemish: 3])

        #expect(pick(candidates, layer: .treatment, profile: profile(skinType: .oily), treatmentTags: tags) == "Rich BHA Cream")
    }

    // MARK: - Gentleness

    @Test func beginnerGetsTheGentlerActive() {
        let candidates = [
            catalogProduct(name: "Strong Retinoid", layer: .treatment, tags: [.retinoid]),
            catalogProduct(name: "Niacinamide Serum", layer: .treatment, tags: [.niacinamide]),
        ]
        let tags = RoutineBuilderEngine.preferredTreatmentTags(for: [.blackhead: 3])

        let forBeginner = pick(candidates, layer: .treatment, profile: profile(experience: .beginner), treatmentTags: tags)
        #expect(forBeginner == "Niacinamide Serum")
    }

    /// ...but a demanding active is still reachable when it's all there is,
    /// rather than the step silently going empty.
    @Test func demandingActiveStillWinsWhenItIsTheOnlyOption() {
        let candidates = [catalogProduct(name: "Strong Retinoid", layer: .treatment, tags: [.retinoid])]
        let tags = RoutineBuilderEngine.preferredTreatmentTags(for: [.blackhead: 3])

        #expect(pick(candidates, layer: .treatment, profile: profile(experience: .beginner), treatmentTags: tags) == "Strong Retinoid")
    }

    @Test func sensitiveSkinPrefersAProductThatSaysItIsGentle() {
        let candidates = [
            catalogProduct(name: "Daily Cleanser", layer: .cleanser),
            catalogProduct(name: "Gentle Soothing Cleanser", layer: .cleanser),
        ]
        #expect(pick(candidates, profile: profile(sensitivity: .sensitive)) == "Gentle Soothing Cleanser")
    }

    // MARK: - Conflict avoidance

    /// Suggesting something that fights what the user already owns is worse
    /// than suggesting the blander option.
    @Test func candidateConflictingWithTheCabinetLoses() {
        let candidates = [
            catalogProduct(name: "AHA Exfoliant", layer: .treatment, tags: [.exfoliatingAcid]),
            catalogProduct(name: "Niacinamide Serum", layer: .treatment, tags: [.niacinamide]),
        ]
        let owned = [ownedProduct(name: "Night Retinoid", tags: [.retinoid])]

        #expect(pick(candidates, layer: .treatment, profile: profile(), owned: owned) == "Niacinamide Serum")
    }

    // MARK: - Determinism

    /// Catalog row order must not decide the routine.
    @Test func resultDoesNotDependOnCatalogOrder() {
        let a = catalogProduct(name: "Cleanser A", layer: .cleanser)
        let b = catalogProduct(name: "Cleanser B", layer: .cleanser)
        let forward = pick([a, b], profile: profile())
        let reversed = pick([b, a], profile: profile())

        #expect(forward == reversed)
        // Exact ties resolve alphabetically.
        #expect(forward == "Cleanser A")
    }

    @Test func emptyCandidateListYieldsNothing() {
        #expect(pick([], profile: profile()) == nil)
    }
}
