//
//  CameraCaptureView.swift
//  Regimen
//

import SwiftUI
import UIKit

/// `UIImagePickerController` is deprecated for browsing the photo library
/// (superseded by `PhotosPicker`), but as of iOS 17 there is still no native
/// SwiftUI API for invoking the system camera UI directly — this remains
/// the standard bridge for that one purpose.
struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        // Every photo this app wants is a selfie, and the scan model is
        // trained on front-facing head shots (see `SkinScanService`).
        // Opening on the rear camera meant flipping it by hand every single
        // time. Guarded because the front camera isn't guaranteed to exist.
        if UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }
        picker.cameraOverlayView = makeGuideOverlay(for: picker.view.bounds)
        picker.delegate = context.coordinator
        return picker
    }

    /// A face outline over the viewfinder.
    ///
    /// The scan model was trained on well-lit, front-facing head shots, and
    /// nothing in the app previously asked for one -- which is where
    /// "couldn't find a face" came from, and why two photos taken a month
    /// apart were rarely framed alike enough to compare honestly. A guide
    /// costs nothing and fixes both.
    ///
    /// Non-interactive on purpose: an overlay that swallowed touches would
    /// take the shutter button with it.
    private func makeGuideOverlay(for bounds: CGRect) -> UIView {
        let overlay = UIView(frame: bounds)
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false

        let ovalWidth = bounds.width * 0.62
        let ovalHeight = ovalWidth * 1.35
        let ovalRect = CGRect(
            x: (bounds.width - ovalWidth) / 2,
            // Sits above centre: the viewfinder's lower third is taken up
            // by the camera's own controls.
            y: bounds.height * 0.22,
            width: ovalWidth,
            height: ovalHeight
        )

        let guideLayer = CAShapeLayer()
        guideLayer.path = UIBezierPath(ovalIn: ovalRect).cgPath
        guideLayer.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
        guideLayer.fillColor = UIColor.clear.cgColor
        guideLayer.lineWidth = 2
        guideLayer.lineDashPattern = [8, 6]
        overlay.layer.addSublayer(guideLayer)

        let hint = UILabel(frame: CGRect(
            x: 0,
            y: ovalRect.maxY + 12,
            width: bounds.width,
            height: 40
        ))
        hint.text = "Fill the oval, face the light"
        hint.textAlignment = .center
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 15, weight: .semibold)
        hint.shadowColor = UIColor.black.withAlphaComponent(0.6)
        hint.shadowOffset = CGSize(width: 0, height: 1)
        overlay.addSubview(hint)

        return overlay
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
