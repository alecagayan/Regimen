//
//  BarcodeScannerView.swift
//  Regimen
//

import AVFoundation
import SwiftUI
import UIKit
import Vision

/// Points the camera at a product's barcode and hands back the digits.
///
/// Typing a product in by hand is the most expensive moment in the app --
/// name, brand, step, size, ingredients -- and it sits directly between a
/// new user and anything working. A barcode collapses all of it into one
/// gesture.
///
/// Resolution is the caller's job (see `ProductEditView`): this view knows
/// only how to read a number off a box.
struct BarcodeScannerView: View {
    var onScanned: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                BarcodeCameraView(
                    onScanned: { code in
                        onScanned(code)
                        dismiss()
                    },
                    onFailure: { errorMessage = $0 }
                )
                .ignoresSafeArea()

                if let errorMessage {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "camera.metering.unknown")
                            .font(.system(size: 40))
                        Text(errorMessage)
                            .font(.bodyText)
                            .multilineTextAlignment(.center)

                        // Telling someone to visit Settings and making
                        // them find it are different things; only the app
                        // can open its own page there.
                        if let settings = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: settings)
                                .font(.controlLabel)
                                .foregroundStyle(Color.brand)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.xl)
                    .background(.black.opacity(0.75))
                } else {
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                            .frame(height: 150)
                            .padding(.horizontal, Theme.Spacing.xl)
                        Text("Line up the barcode")
                            .font(.controlLabel)
                            .foregroundStyle(.white)
                            .padding(.top, Theme.Spacing.md)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The AVFoundation half. Kept as a `UIViewControllerRepresentable` because
/// a capture session needs a real view whose layer it can attach a preview
/// to, and a lifecycle to start and stop against.
private struct BarcodeCameraView: UIViewControllerRepresentable {
    var onScanned: (String) -> Void
    var onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCaptureController {
        let controller = BarcodeCaptureController()
        controller.onScanned = onScanned
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeCaptureController, context: Context) {}
}

final class BarcodeCaptureController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScanned: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// One result only: the delegate fires continuously while a barcode is
    /// in frame, and without this the caller would be handed the same code
    /// dozens of times.
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessThenConfigure()
    }

    /// Camera permission has to be checked explicitly, before configuring.
    ///
    /// A *denied* permission still hands back a perfectly valid
    /// `AVCaptureDevice`, so the guard below passes, the session starts,
    /// and the preview stays black forever with nothing said. That is what
    /// this screen used to do -- and denying permissions is one of the
    /// first things App Review tries.
    private func requestAccessThenConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                    } else {
                        self.reportNoCameraAccess()
                    }
                }
            }
        case .denied, .restricted:
            reportNoCameraAccess()
        @unknown default:
            reportNoCameraAccess()
        }
    }

    /// Says what happened and what to do about it. "Couldn't start the
    /// scanner" would be true but useless -- the fix is in Settings, and
    /// the user has no way to guess that from a black rectangle.
    private func reportNoCameraAccess() {
        onFailure?("Regimen doesn't have camera access. Turn it on in Settings › Regimen to scan barcodes.")
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            onFailure?("This device's camera isn't available.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onFailure?("Couldn't start the barcode scanner.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // The symbologies actually printed on retail packaging. EAN-13
        // covers most of the world; UPC-A is North America.
        output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        // startRunning blocks; keeping it off the main thread is what stops
        // the sheet's presentation animation from hitching.
        Task.detached { [session] in
            session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Task.detached { [session] in
            session.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue
        else { return }
        hasScanned = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScanned?(code)
    }
}
