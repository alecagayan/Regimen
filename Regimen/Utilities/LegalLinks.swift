//
//  LegalLinks.swift
//  Regimen
//

import Foundation

/// The URLs App Review expects to find inside the app.
///
/// Guideline 3.1.2 requires a subscription screen to show functional links
/// to both the Terms of Use (EULA) and the Privacy Policy -- not just in
/// App Store Connect, but in the app itself. Missing links here are one of
/// the most common automatic rejections for subscription apps, and this
/// app previously had neither anywhere in its UI.
enum LegalLinks {
    /// Hosted from `/docs` on the repo's GitHub Pages site. The same URL
    /// goes in App Store Connect, and App Review does open it.
    static let privacyPolicy = URL(string: "https://alecagayan.github.io/Regimen/privacy-policy")!

    /// Apple's standard EULA, which is the licence that applies unless a
    /// custom one is supplied in App Store Connect. Linking Apple's own
    /// text is the simplest way to satisfy 3.1.2 without taking on a
    /// bespoke agreement that would then need to be kept accurate.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
