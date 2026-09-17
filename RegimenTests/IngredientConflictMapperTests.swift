//
//  IngredientConflictMapperTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

/// Deriving conflict tags from an ingredient list is string matching over
/// INCI names, where the near-misses are real products whose meanings are
/// opposites. These pin the distinctions that matter.
struct IngredientConflictMapperTests {

    // MARK: - The basics

    @Test func retinolIsARetinoid() {
        #expect(IngredientConflictMapper.tags(for: ["Aqua", "Retinol", "Squalane"]).contains(.retinoid))
    }

    @Test func salicylicAcidIsAnExfoliant() {
        #expect(IngredientConflictMapper.tags(for: ["Aqua", "Salicylic Acid"]).contains(.exfoliatingAcid))
    }

    @Test func anEmptyListDerivesNothing() {
        #expect(IngredientConflictMapper.tags(for: []).isEmpty)
    }

    @Test func aPlainMoisturizerDerivesNothing() {
        let tags = IngredientConflictMapper.tags(for: ["Aqua", "Glycerin", "Cetearyl Alcohol", "Shea Butter"])
        #expect(tags.isEmpty)
    }

    // MARK: - The distinctions that would cry wolf

    /// Citric acid is a pH adjuster in a large share of all cosmetics. If
    /// it registered as an exfoliating acid, most of the cabinet would
    /// carry a conflict banner and the user would learn to ignore them.
    @Test func citricAcidIsNotAnExfoliant() {
        let tags = IngredientConflictMapper.tags(for: ["Aqua", "Glycerin", "Citric Acid"])
        #expect(!tags.contains(.exfoliatingAcid))
    }

    @Test func hyaluronicAcidIsNotAnExfoliant() {
        #expect(!IngredientConflictMapper.tags(for: ["Sodium Hyaluronate", "Hyaluronic Acid"]).contains(.exfoliatingAcid))
    }

    /// The single most important distinction in the whole table: pure
    /// L-ascorbic acid conflicts with niacinamide on pH grounds, and the
    /// derivatives specifically do not. "ethyl ascorbic acid" contains the
    /// literal substring "ascorbic acid", so a substring match would get
    /// this exactly backwards.
    @Test func ethylAscorbicAcidIsADerivativeNotPureVitaminC() {
        let tags = IngredientConflictMapper.tags(for: ["Aqua", "3-O-Ethyl Ascorbic Acid"])
        #expect(tags.contains(.vitaminCDerivative))
        #expect(!tags.contains(.pureVitaminC))
    }

    @Test func plainAscorbicAcidIsPureVitaminC() {
        let tags = IngredientConflictMapper.tags(for: ["Aqua", "Ascorbic Acid", "Ferulic Acid"])
        #expect(tags.contains(.pureVitaminC))
        #expect(!tags.contains(.vitaminCDerivative))
    }

    /// "retinal" is a prefix of "retinaldehyde", and both are retinoids, so
    /// the risk here is not a wrong tag but a crash of logic -- this pins
    /// that the longer name still resolves.
    @Test func retinaldehydeIsARetinoid() {
        #expect(IngredientConflictMapper.tags(for: ["Retinaldehyde"]).contains(.retinoid))
    }

    // MARK: - Real-world formatting

    @Test func qualifiedNamesStillMatch() {
        #expect(IngredientConflictMapper.tags(for: ["Salicylic Acid (BHA)"]).contains(.exfoliatingAcid))
        #expect(IngredientConflictMapper.tags(for: ["Retinol 0.5%"]).contains(.retinoid))
    }

    /// INCI lists carry trailing punctuation and certification asterisks.
    @Test func trailingPunctuationIsIgnored() {
        #expect(IngredientConflictMapper.tags(for: ["Niacinamide,", "Glycerin*"]).contains(.niacinamide))
    }

    @Test func caseDoesNotMatter() {
        #expect(IngredientConflictMapper.tags(for: ["BENZOYL PEROXIDE"]).contains(.benzoylPeroxide))
    }

    // MARK: - Ordering and evidence

    @Test func tagsComeBackInAStableOrder() {
        let list = ["Niacinamide", "Retinol", "Glycolic Acid"]
        #expect(IngredientConflictMapper.tags(for: list) == IngredientConflictMapper.tags(for: list.reversed()))
    }

    @Test func evidenceNamesTheIngredientThatCausedTheTag() {
        let evidence = IngredientConflictMapper.evidence(for: .retinoid, in: ["Aqua", "Retinol", "Glycerin"])
        #expect(evidence == ["retinol"])
    }

    @Test func evidenceIsEmptyForATagThatWasNotFound() {
        #expect(IngredientConflictMapper.evidence(for: .benzoylPeroxide, in: ["Aqua", "Retinol"]).isEmpty)
    }
}

/// The point of the mapper: products that were never tagged by hand still
/// take part in conflict checking.
struct EffectiveConflictTagTests {

    private func product(name: String, tags: [ConflictTag] = [], ingredients: [String] = []) -> Product {
        Product(
            userID: UUID(),
            name: name,
            brand: "Brand",
            routineTime: .pm,
            layerCategory: .treatment,
            applicationOrder: 1,
            conflictTags: tags,
            sizeInML: 30,
            openedDate: .now,
            ingredients: ingredients
        )
    }

    @Test func explicitTagsAreKept() {
        let item = product(name: "Serum", tags: [.retinoid])
        #expect(item.effectiveConflictTags == [.retinoid])
    }

    @Test func ingredientsAloneAreEnoughToBeTagged() {
        let item = product(name: "Untagged Serum", ingredients: ["Aqua", "Retinol"])
        #expect(item.conflictTags.isEmpty)
        #expect(item.effectiveConflictTags.contains(.retinoid))
    }

    @Test func explicitAndDerivedAreUnionedWithoutDuplicates() {
        let item = product(name: "Serum", tags: [.retinoid], ingredients: ["Retinol", "Niacinamide"])
        #expect(Set(item.effectiveConflictTags) == [.retinoid, .niacinamide])
        #expect(item.effectiveConflictTags.count == 2)
    }

    @Test func derivedExcludesWhatIsAlreadyExplicit() {
        let item = product(name: "Serum", tags: [.retinoid], ingredients: ["Retinol"])
        #expect(item.derivedConflictTags.isEmpty)
    }

    /// The whole point, end to end: two hand-entered products with no tags
    /// at all now produce a conflict off their ingredient lists.
    @Test func untaggedProductsStillConflict() {
        let retinoid = product(name: "Night Serum", ingredients: ["Aqua", "Retinol"])
        let acid = product(name: "Exfoliant", ingredients: ["Aqua", "Glycolic Acid"])

        let conflicts = ConflictChecker.conflicts(among: [retinoid, acid])
        #expect(conflicts.count == 1)
    }

    @Test func unrelatedUntaggedProductsDoNotConflict() {
        let cleanser = product(name: "Cleanser", ingredients: ["Aqua", "Glycerin"])
        let moisturizer = product(name: "Moisturizer", ingredients: ["Aqua", "Shea Butter"])

        #expect(ConflictChecker.conflicts(among: [cleanser, moisturizer]).isEmpty)
    }
}
