//
//  ShareSheet.swift
//  Regimen
//

import SwiftUI
import UIKit

/// Thin bridge to `UIActivityViewController`.
///
/// SwiftUI's own `ShareLink` covers most cases, but it needs its content up
/// front at view-construction time; this is for the places where what gets
/// shared is built on demand (a rendered progress card, an export file
/// written just before presenting).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Lets a plain `URL` drive `.sheet(item:)`, which needs `Identifiable`.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
