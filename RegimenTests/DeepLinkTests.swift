//
//  DeepLinkTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

/// Deep links are parsed in one place and consumed in two -- `RootView`
/// handles password recovery, `ContentView` handles tab routing, and both
/// receive every URL. These pin that each ignores the other's links, which
/// is what keeps a reset link from dumping the user on a random tab.
struct DeepLinkTests {

    // MARK: - Routing

    @Test func routineLinkCarriesItsTimeOfDay() {
        #expect(AppDestination(url: URL(string: "regimen://routine?time=PM")!) == .routine(.pm))
        #expect(AppDestination(url: URL(string: "regimen://routine?time=AM")!) == .routine(.am))
    }

    /// A bare routine link should open the tab without overriding whichever
    /// half of the day the clock says it is.
    @Test func aBareRoutineLinkPinsNoTime() {
        #expect(AppDestination(url: URL(string: "regimen://routine")!) == .routine(nil))
    }

    @Test func eachTabHasALink() {
        #expect(AppDestination(url: URL(string: "regimen://reorder")!) == .reorder)
        #expect(AppDestination(url: URL(string: "regimen://progress")!) == .progress)
        #expect(AppDestination(url: URL(string: "regimen://cabinet")!) == .cabinet)
    }

    // MARK: - What must NOT route

    /// The one that matters: the recovery link is handled by `RootView`,
    /// and `ContentView` sees it too. If this parsed to a destination,
    /// opening a reset email would also yank the user to a tab mid-flow.
    @Test func aPasswordResetLinkIsNotADestination() {
        #expect(AppDestination(url: URL(string: "regimen://reset-password#access_token=abc")!) == nil)
    }

    @Test func anUnknownHostRoutesNowhere() {
        #expect(AppDestination(url: URL(string: "regimen://nonsense")!) == nil)
    }

    /// Another app's scheme must never move this app around.
    @Test func aForeignSchemeIsIgnored() {
        #expect(AppDestination(url: URL(string: "https://routine")!) == nil)
        #expect(AppDestination(url: URL(string: "othernapp://routine?time=AM")!) == nil)
    }

    /// A malformed time is not a reason to refuse the whole link -- open
    /// the tab, just don't pin a half of the day that wasn't understood.
    @Test func anUnrecognisedTimeStillOpensTheTab() {
        #expect(AppDestination(url: URL(string: "regimen://routine?time=EVENING")!) == .routine(nil))
    }

    // MARK: - Construction

    /// The widget builds these and the app parses them, in two separate
    /// processes. A round trip is the only thing that proves they agree.
    @Test func builtLinksParseBackToWhatBuiltThem() throws {
        let am = try #require(AppDeepLink.routine(timeOfDay: "AM"))
        #expect(AppDestination(url: am) == .routine(.am))

        let bare = try #require(AppDeepLink.routine())
        #expect(AppDestination(url: bare) == .routine(nil))

        let cabinet = try #require(AppDeepLink.tab("cabinet"))
        #expect(AppDestination(url: cabinet) == .cabinet)
    }

    @Test func theResetLinkUsesTheAppsOwnScheme() throws {
        let reset = try #require(AppDeepLink.passwordReset)
        #expect(reset.scheme == AppDeepLink.scheme)
        // Registered as a Redirect URL in Supabase; a mismatch here means
        // the emailed link is rejected before it reaches the app.
        #expect(reset.absoluteString == "regimen://reset-password")
    }
}
