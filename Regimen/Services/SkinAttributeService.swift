//
//  SkinAttributeService.swift
//  Regimen
//

import CoreML
import UIKit

/// Whole-face binary classifiers trained on killa92's own severity labels
/// (see RegimenSkinModel/src/train_killa92_attribute.py). Of 12 columns
/// tried, only these 3 beat their majority-class baseline by a real
/// margin with non-trivial minority-class recall -- oiliness, dehydration,
/// pores, irritation, redness, elasticity, freckles, and post-acne-marks
/// did not, and are deliberately not shipped. A 4th, fine-lines-around-eyes,
/// also passed but needs an eye-region crop -- held back rather than
/// silently reintroducing eye-area detection after it was explicitly
/// removed from this app once already.
enum SkinAttribute: String, CaseIterable {
    case sensitivity = "SensitivityModel"
    case darkSpots = "DarkSpotsModel"
    case unevenSkin = "UnevenSkinModel"

    var label: String {
        switch self {
        case .sensitivity: "Sensitive-looking skin"
        // Not "Dark spots" -- that's LesionClass.spot in SkinScanService,
        // which *is* highlighted (a real detected, located patch). This
        // classifier has no location at all, just a whole-face yes/no, so
        // its label says so rather than implying the same kind of finding.
        case .darkSpots: "Widespread dark-spot look"
        case .unevenSkin: "Uneven skin tone"
        }
    }
}

/// Runs the whole-face attribute classifiers on the same face crop
/// `SkinScanService` already produces -- fully on-device, same as
/// everything else in this pipeline.
@MainActor
final class SkinAttributeService {
    static let shared = SkinAttributeService()
    private init() {}

    private var models: [SkinAttribute: MLModel] = [:]
    // Small-data (n<30 validation examples per attribute) classifiers --
    // a conservative bar so a near-coinflip prediction doesn't read as a
    // confident finding.
    private let threshold = 0.6

    private func model(for attribute: SkinAttribute) async throws -> MLModel {
        if let cached = models[attribute] { return cached }
        guard let url = Bundle.main.url(forResource: attribute.rawValue, withExtension: "mlmodelc") else {
            throw SkinScanError.imageConversionFailed
        }
        let loaded = try await MLModel.load(contentsOf: url, configuration: .appDefault)
        models[attribute] = loaded
        return loaded
    }

    func classify(faceCGImage: CGImage) async -> [SkinAttribute] {
        var flagged: [SkinAttribute] = []
        for attribute in SkinAttribute.allCases {
            guard let probability = try? await predict(attribute: attribute, cgImage: faceCGImage) else { continue }
            print("SkinAttributeService \(attribute.rawValue): p=\(String(format: "%.2f", probability))")
            if probability >= threshold {
                flagged.append(attribute)
            }
        }
        return flagged
    }

    /// Builds the input feature provider directly (no per-model codegen'd
    /// Input/Output types) so one function serves all attribute models --
    /// the exact recipe Xcode's generated `imageWith:` convenience inits
    /// use under the hood, just written once instead of once per model.
    private func predict(attribute: SkinAttribute, cgImage: CGImage) async throws -> Double {
        let model = try await model(for: attribute)
        guard let pixelBuffer = try MLFeatureValue(
            cgImage: cgImage,
            pixelsWide: 224,
            pixelsHigh: 224,
            pixelFormatType: kCVPixelFormatType_32ARGB,
            options: nil
        ).imageBufferValue else {
            throw SkinScanError.imageConversionFailed
        }
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)])
        let output = try await model.prediction(from: input, options: MLPredictionOptions())
        guard let value = output.featureValue(for: "value")?.multiArrayValue else {
            throw SkinScanError.imageConversionFailed
        }
        return value[0].doubleValue
    }
}
