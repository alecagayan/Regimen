//
//  SkinScanService.swift
//  Regimen
//

import CoreML
import SwiftUI

/// Everything a scan can surface to the user, all from the SkinScanModel
/// segmentation mask. (An under-eye dark-circle classifier was tried as a
/// third kind and removed by request -- its 69%-accuracy signal plus
/// unreliable Simulator eye landmarks made placement more annoying than
/// useful. The training side lives on in RegimenSkinModel/src/eye_bags_*.)
enum FindingKind: String, CaseIterable, Codable, Hashable {
    case blemish
    case spot
    case blackhead
    case whitehead

    var singular: String {
        switch self {
        case .blemish: "blemish area"
        case .spot: "dark spot"
        case .blackhead: "blackhead"
        case .whitehead: "whitehead"
        }
    }

    var plural: String {
        switch self {
        case .blemish: "blemish areas"
        case .spot: "dark spots"
        case .blackhead: "blackheads"
        case .whitehead: "whiteheads"
        }
    }

    var tint: Color {
        switch self {
        case .blemish: .orange
        case .spot: .purple
        case .blackhead: .brown
        case .whitehead: .mint
        }
    }
}

/// The segmentation mask's channels. Order and weights must match
/// RegimenSkinModel/src/segmentation_dataset.py's CLASSES/CLASS_WEIGHTS.
enum LesionClass: Int, CaseIterable {
    case blemish = 0
    case spot = 1
    case blackhead = 2
    case whitehead = 3

    var kind: FindingKind {
        switch self {
        case .blemish: .blemish
        case .spot: .spot
        case .blackhead: .blackhead
        case .whitehead: .whitehead
        }
    }

    var severityWeight: Double {
        switch self {
        case .blemish: 1.0
        case .spot: 0.5
        case .blackhead: 0.3
        case .whitehead: 0.3
        }
    }
}

/// Face regions used to localize findings in plain language ("2 blemish
/// areas on your forehead"), derived purely from the detected face box's
/// geometry -- no extra model.
enum FaceZone: String, CaseIterable, Codable {
    case forehead
    case nose
    case leftCheek = "left cheek"
    case rightCheek = "right cheek"
    case chin

    var label: String {
        switch self {
        case .forehead: "Forehead"
        case .nose: "Nose"
        case .leftCheek: "Left Cheek"
        case .rightCheek: "Right Cheek"
        case .chin: "Chin"
        }
    }
}

/// One contiguous flagged region.
struct SkinFinding: Identifiable {
    let id = UUID()
    let kind: FindingKind
    let zone: FaceZone
    /// Flagged cells in this region -- a rough size proxy (each cell is
    /// 1/56th of the face crop per side), not a physical measurement.
    let cellCount: Int
}

/// One full scan of one photo.
struct SkinScanResult {
    /// 0-100, higher = clearer skin.
    let score: Double
    /// Every contiguous flagged region, with its kind and face zone.
    let findings: [SkinFinding]
    /// Colored translucent patches, sized to be drawn over `faceRect`.
    /// Nil when nothing was flagged.
    let overlay: UIImage?
    /// Normalized (top-left-origin) region of the full photo the scan ran
    /// on and that `overlay` maps onto.
    let faceRect: CGRect
    /// Whole-face attributes flagged by `SkinAttributeService` -- not
    /// spatial (no zone/overlay), just "this looks present or not".
    let attributes: [SkinAttribute]

    /// Rough count of distinct flagged regions per kind -- an estimate,
    /// not a clinical count.
    var counts: [FindingKind: Int] {
        findings.reduce(into: [:]) { counts, finding in counts[finding.kind, default: 0] += 1 }
    }
}

enum SkinScanError: Error {
    case imageConversionFailed
    case noFaceDetected
}

/// Runs the skin scan over the face region of a photo: one segmentation
/// model producing both the highlighted patches and the skin score.
/// Fully on-device — the photo is never sent anywhere to be scored.
@MainActor
final class SkinScanService {
    static let shared = SkinScanService()
    private init() {}

    private var maskModel: SkinScanModel?

    private let maskSize = 56
    // Two threshold sets on purpose. The overlay leans toward recall
    // (missing a visible spot reads as broken; a soft extra patch doesn't),
    // while the score sticks to whatever thresholds are dice-optimal (see
    // RegimenSkinModel/src/evaluate_segmentation.py's sweep). whitehead is
    // pinned above 1.0 -- a probability that can never be exceeded -- so it
    // never appears in a finding or contributes to the score: its trained
    // dice (0.08) never rose meaningfully above noise even though blackhead,
    // trained on the same acne-6rzah volume, reached 0.256. Whiteheads are
    // visually far more subtle than blackheads' distinctive dark color, and
    // this data didn't carry enough signal to trust surfacing it. The
    // channel stays in the model and this enum (removing it would shift
    // every later channel's index and silently corrupt decoding) -- it's
    // just never allowed to fire.
    private let displayThresholds: [LesionClass: Double] = [.blemish: 0.7, .spot: 0.4, .blackhead: 0.6, .whitehead: 1.01]
    private let scoreThresholds: [LesionClass: Double] = [.blemish: 0.9, .spot: 0.5, .blackhead: 0.8, .whitehead: 1.01]
    // The model trained on head-shot portraits (acne-cv), so scans run on
    // a padded Vision face crop to match that framing.
    private let facePaddingFraction: CGFloat = 0.4
    // score = clip(slope * weightedCoverage + intercept, 0, 100), fit on
    // the validation set against the lesion-count clarity target (v4b
    // model, blackhead added and balanced against acne-6rzah's much larger
    // volume: R^2 0.29 / MAE 9.0 vs 10.6 for predicting the mean -- the
    // best of any version so far). The constants come from the threshold
    // sweep in evaluate_segmentation and must be re-copied whenever the
    // model is retrained.
    private let scoreSlope = -1286.9
    private let scoreIntercept = 89.8

    private func loadModelsIfNeeded() async throws {
        if maskModel == nil {
            maskModel = try await SkinScanModel.load(configuration: .appDefault)
        }
    }

    func scan(_ image: UIImage) async throws -> SkinScanResult {
        try await loadModelsIfNeeded()
        // Camera JPEGs store rotated pixels plus an EXIF orientation flag:
        // UIImage *displays* them upright, but `.cgImage` is the raw
        // rotated buffer. Skipping this normalization once put every
        // Vision result (face box, eye landmarks) in rotated-pixel space
        // while the overlay drew in upright display space -- the face box
        // came back spanning 84% of the photo's height and the two eyes
        // sat on a diagonal. Everything downstream assumes upright pixels.
        guard let cgImage = image.orientedUp().cgImage else {
            throw SkinScanError.imageConversionFailed
        }

        guard let faceBox = try FaceRegionLocator.faceBoundingBox(in: cgImage) else {
            throw SkinScanError.noFaceDetected
        }
        let faceRect = FaceRegionLocator
            .padded(faceBox, fraction: facePaddingFraction)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !faceRect.isEmpty, let faceCGImage = FaceRegionLocator.crop(cgImage, to: faceRect) else {
            throw SkinScanError.noFaceDetected
        }

        print("SkinScanService faceBox \(faceBox.integralDescription), crop \(faceRect.integralDescription)")

        let input = try SkinScanModelInput(imageWith: faceCGImage)
        let output = try await maskModel!.prediction(input: input)
        var probabilities = probabilities(output.mask)
        clipToFaceEllipse(&probabilities, faceBox: faceBox, faceRect: faceRect)

        let displayBinary = binarize(probabilities, thresholds: displayThresholds)
        let scoreBinary = binarize(probabilities, thresholds: scoreThresholds)

        // The calibration was fit without the ellipse clip, so post-clip
        // coverage skews slightly low (background false positives that the
        // fit absorbed are now removed) -- scores read a touch higher than
        // the calibration MAE suggests, in a consistent direction.
        let coverage = weightedCoverage(scoreBinary)
        let score = min(max(scoreSlope * coverage + scoreIntercept, 0), 100)

        for lesionClass in LesionClass.allCases {
            let peak = probabilities[lesionClass.rawValue].max() ?? 0
            let shown = displayBinary[lesionClass.rawValue].lazy.filter { $0 }.count
            print("SkinScanService \(lesionClass.kind.singular): peak \(String(format: "%.2f", peak)), \(shown) cells shown")
        }
        print("SkinScanService: coverage \(String(format: "%.4f", coverage)) -> score \(String(format: "%.0f", score))")

        let attributes = await SkinAttributeService.shared.classify(faceCGImage: faceCGImage)

        return SkinScanResult(
            score: score,
            findings: findings(in: displayBinary, faceBox: faceBox, faceRect: faceRect),
            overlay: overlayImage(displayBinary),
            faceRect: faceRect,
            attributes: attributes
        )
    }

    /// Maps a mask-cell centroid (crop-normalized) to a face zone via the
    /// detected face box's geometry. Bands are approximate by design --
    /// "forehead" vs "left cheek" level, not landmark-precise.
    private func zone(forCropX cropX: Double, cropY: Double, faceBox: CGRect, faceRect: CGRect) -> FaceZone {
        let boxX = (cropX * faceRect.width + faceRect.minX - faceBox.minX) / faceBox.width
        let boxY = (cropY * faceRect.height + faceRect.minY - faceBox.minY) / faceBox.height
        // Above 0.33 of the box covers the forehead band; anything above
        // the box's own top (negative boxY -- the clip ellipse extends
        // there deliberately) is forehead too.
        if boxY < 0.33 { return .forehead }
        if boxY >= 0.75 { return .chin }
        if boxX < 0.35 { return .leftCheek }
        if boxX >= 0.65 { return .rightCheek }
        return .nose
    }

    // MARK: - Mask decoding

    /// MLMultiArray -> per-class probability grid, indexed
    /// [class][y * maskSize + x].
    ///
    /// The layout is resolved from the array's actual shape rather than
    /// assumed: the converter produced (1, 56, 56, 2) in Python, but
    /// legacy-neuralnetwork-format models are entitled to hand back a
    /// channels-first (or extra-leading-dim) MLMultiArray on device, and a
    /// hardcoded index order would silently read garbage in that case.
    private func probabilities(_ mask: MLMultiArray) -> [[Double]] {
        let shape = mask.shape.map(\.intValue)
        let classCount = LesionClass.allCases.count
        // Positions of the meaningful axes: the (at most one) axis sized
        // classCount, and the two sized maskSize; every other axis must be
        // size 1 and is pinned to index 0.
        let classAxis = shape.firstIndex(of: classCount)
        let spatialAxes = shape.indices.filter { shape[$0] == maskSize }
        guard spatialAxes.count == 2 else {
            print("SkinScanService: unexpected mask shape \(shape), skipping decode")
            return [[Double]](repeating: [Double](repeating: 0, count: maskSize * maskSize), count: classCount)
        }

        var probabilities = [[Double]](repeating: [Double](repeating: 0, count: maskSize * maskSize), count: classCount)
        var index = [NSNumber](repeating: 0, count: shape.count)
        for lesionClass in LesionClass.allCases {
            if let classAxis { index[classAxis] = NSNumber(value: lesionClass.rawValue) }
            for y in 0..<maskSize {
                index[spatialAxes[0]] = NSNumber(value: y)
                for x in 0..<maskSize {
                    index[spatialAxes[1]] = NSNumber(value: x)
                    probabilities[lesionClass.rawValue][y * maskSize + x] = mask[index].doubleValue
                }
            }
        }
        return probabilities
    }

    /// Zeroes out every cell outside an ellipse fit to the detected face,
    /// so highlights can never land on the wall, hair, or shoulders that
    /// the padded crop pulls in. Horizontally the ellipse matches the face
    /// box exactly (a first pass at 1.15x let a wall cell survive at the
    /// ellipse's widest point -- blemishes don't live past the face
    /// silhouette, so there's nothing to gain from the margin); vertically
    /// it extends 40% (shifted slightly upward), because Vision's face
    /// rectangle crops at mid-forehead and forehead skin is squarely
    /// something the scan should keep.
    private func clipToFaceEllipse(_ probabilities: inout [[Double]], faceBox: CGRect, faceRect: CGRect) {
        let centerX = (faceBox.midX - faceRect.minX) / faceRect.width
        let centerY = (faceBox.midY - 0.05 * faceBox.height - faceRect.minY) / faceRect.height
        let semiX = (faceBox.width / 2) / faceRect.width
        let semiY = (faceBox.height * 1.4 / 2) / faceRect.height
        guard semiX > 0, semiY > 0 else { return }

        for y in 0..<maskSize {
            let normY = (CGFloat(y) + 0.5) / CGFloat(maskSize)
            for x in 0..<maskSize {
                let normX = (CGFloat(x) + 0.5) / CGFloat(maskSize)
                let dx = (normX - centerX) / semiX
                let dy = (normY - centerY) / semiY
                if dx * dx + dy * dy > 1 {
                    for channel in probabilities.indices {
                        probabilities[channel][y * maskSize + x] = 0
                    }
                }
            }
        }
    }

    private func binarize(_ probabilities: [[Double]], thresholds: [LesionClass: Double]) -> [[Bool]] {
        LesionClass.allCases.map { lesionClass in
            let threshold = thresholds[lesionClass] ?? 0.5
            return probabilities[lesionClass.rawValue].map { $0 > threshold }
        }
    }

    private func weightedCoverage(_ binary: [[Bool]]) -> Double {
        var total = 0.0
        for lesionClass in LesionClass.allCases {
            let flagged = binary[lesionClass.rawValue].lazy.filter { $0 }.count
            total += lesionClass.severityWeight * Double(flagged) / Double(maskSize * maskSize)
        }
        return total
    }

    /// Connected components (4-connectivity) per class, each mapped to a
    /// face zone via its centroid -- turns the raw mask into
    /// "2 blemish areas on your forehead, 1 dark spot on your left cheek".
    private func findings(in binary: [[Bool]], faceBox: CGRect, faceRect: CGRect) -> [SkinFinding] {
        var results: [SkinFinding] = []
        for lesionClass in LesionClass.allCases {
            var visited = [Bool](repeating: false, count: maskSize * maskSize)
            let grid = binary[lesionClass.rawValue]
            for start in 0..<grid.count where grid[start] && !visited[start] {
                var stack = [start]
                visited[start] = true
                var cells: [Int] = []
                while let cell = stack.popLast() {
                    cells.append(cell)
                    let x = cell % maskSize
                    let y = cell / maskSize
                    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                        guard (0..<maskSize).contains(nx), (0..<maskSize).contains(ny) else { continue }
                        let neighbor = ny * maskSize + nx
                        if grid[neighbor] && !visited[neighbor] {
                            visited[neighbor] = true
                            stack.append(neighbor)
                        }
                    }
                }

                let centroidX = (cells.map { Double($0 % maskSize) }.reduce(0, +) / Double(cells.count) + 0.5) / Double(maskSize)
                let centroidY = (cells.map { Double($0 / maskSize) }.reduce(0, +) / Double(cells.count) + 0.5) / Double(maskSize)
                results.append(SkinFinding(
                    kind: lesionClass.kind,
                    zone: zone(forCropX: centroidX, cropY: centroidY, faceBox: faceBox, faceRect: faceRect),
                    cellCount: cells.count
                ))
            }
        }
        return results
    }

    /// Renders the flagged cells plus any under-eye regions as an RGBA
    /// image sized to be drawn over the face crop: translucent fill per
    /// patch, plus a thin near-opaque stroke along each patch's outer edge
    /// so its boundary reads clearly against skin. Rendered at 8x the mask
    /// grid so the stroke can actually be thin.
    private func overlayImage(_ binary: [[Bool]]) -> UIImage? {
        guard binary.contains(where: { $0.contains(true) }) else { return nil }

        let scale: CGFloat = 8
        let renderSize = CGFloat(maskSize) * scale
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: renderSize, height: renderSize), format: format)

        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setLineWidth(2.5)

            // Ascending severity, so the more severe class draws on top
            // where the two overlap.
            for lesionClass in LesionClass.allCases.sorted(by: { $0.severityWeight < $1.severityWeight }) {
                let grid = binary[lesionClass.rawValue]
                let tint = UIColor(lesionClass.kind.tint)

                context.setFillColor(tint.withAlphaComponent(0.35).cgColor)
                for cell in 0..<(maskSize * maskSize) where grid[cell] {
                    let x = CGFloat(cell % maskSize) * scale
                    let y = CGFloat(cell / maskSize) * scale
                    context.fill(CGRect(x: x, y: y, width: scale, height: scale))
                }

                // Stroke only the sides that border an unflagged cell (or
                // the grid edge) -- the union of those sides is exactly
                // each patch's outline, with no interior grid lines.
                context.setStrokeColor(tint.withAlphaComponent(0.9).cgColor)
                context.beginPath()
                for cell in 0..<(maskSize * maskSize) where grid[cell] {
                    let cx = cell % maskSize
                    let cy = cell / maskSize
                    let x = CGFloat(cx) * scale
                    let y = CGFloat(cy) * scale
                    let flagged = { (nx: Int, ny: Int) -> Bool in
                        (0..<self.maskSize).contains(nx) && (0..<self.maskSize).contains(ny)
                            && grid[ny * self.maskSize + nx]
                    }
                    if !flagged(cx, cy - 1) {
                        context.move(to: CGPoint(x: x, y: y))
                        context.addLine(to: CGPoint(x: x + scale, y: y))
                    }
                    if !flagged(cx, cy + 1) {
                        context.move(to: CGPoint(x: x, y: y + scale))
                        context.addLine(to: CGPoint(x: x + scale, y: y + scale))
                    }
                    if !flagged(cx - 1, cy) {
                        context.move(to: CGPoint(x: x, y: y))
                        context.addLine(to: CGPoint(x: x, y: y + scale))
                    }
                    if !flagged(cx + 1, cy) {
                        context.move(to: CGPoint(x: x + scale, y: y))
                        context.addLine(to: CGPoint(x: x + scale, y: y + scale))
                    }
                }
                context.strokePath()
            }
        }
    }
}

private extension CGRect {
    /// Compact "(x, y, w, h)" with 2 decimals, for the diagnostic log.
    var integralDescription: String {
        String(format: "(%.2f, %.2f, %.2f, %.2f)", minX, minY, width, height)
    }
}

private extension UIImage {
    /// Re-renders so the pixel buffer itself is upright, making `.cgImage`
    /// coordinates match what the user sees. A no-op for images that are
    /// already stored upright.
    func orientedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
