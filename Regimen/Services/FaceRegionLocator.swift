//
//  FaceRegionLocator.swift
//  Regimen
//

import Vision

/// Vision-based face detection for `SkinScanService`, kept separate so the
/// bottom-left-origin-to-top-left-origin coordinate conversion (Vision's
/// convention vs. everywhere else in this app) lives in one place.
enum FaceRegionLocator {
    /// The whole face's bounding box, normalized with origin top-left
    /// (0,0 = top-left of the photo, 1,1 = bottom-right) -- nil if no face
    /// is found.
    static func faceBoundingBox(in cgImage: CGImage) throws -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        forceCPUInSimulator(request)
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        guard let face = request.results?.first else { return nil }

        // Vision's boundingBox is normalized with origin bottom-left --
        // flip to top-left origin. The box's bottom edge in Vision-space
        // (y = box.minY) becomes the *larger* y in top-left space, and its
        // top edge (y = box.minY + box.height) becomes the smaller one.
        let box = face.boundingBox
        return CGRect(x: box.minX, y: 1 - box.minY - box.height, width: box.width, height: box.height)
    }

    /// Crops `cgImage` to a normalized (top-left-origin) rect, clamped to
    /// the image's own bounds.
    static func crop(_ cgImage: CGImage, to normalizedRect: CGRect) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let clamped = normalizedRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isEmpty else { return nil }
        let pixelRect = CGRect(
            x: clamped.minX * width,
            y: clamped.minY * height,
            width: clamped.width * width,
            height: clamped.height * height
        ).integral
        return cgImage.cropping(to: pixelRect)
    }

    /// Expands a normalized rect outward by `fraction` on each side.
    static func padded(_ rect: CGRect, fraction: CGFloat) -> CGRect {
        let padX = rect.width * fraction
        let padY = rect.height * fraction
        return CGRect(x: rect.minX - padX, y: rect.minY - padY, width: rect.width + 2 * padX, height: rect.height + 2 * padY)
    }

    /// Same Simulator gap as MLModelConfiguration.appDefault, one framework
    /// over: Vision's detectors fail outright in the Simulator with
    /// "Could not create inference context" (Vision error 9) when they try
    /// to use the emulated GPU/Neural Engine. Pinning every compute stage
    /// to CPU there fixes it; compiled out entirely on real hardware.
    private static func forceCPUInSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        guard let stageDevices = try? request.supportedComputeStageDevices else { return }
        for (stage, devices) in stageDevices {
            let cpu = devices.first {
                if case .cpu = $0 { return true }
                return false
            }
            if let cpu {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        #endif
    }
}
