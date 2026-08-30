//
//  AppNavigation.swift
//  Regimen
//

import SwiftUI

enum AppTab: Hashable {
    case routine
    case reorder
    case progress
    case cabinet
}

/// Cross-tab navigation state, so one screen can hand the user off to the
/// place that actually completes their task.
///
/// This exists because every empty state in the app used to end in a
/// sentence like "add a product in the Cabinet tab" -- correct, but it left
/// the user to go find it. On a brand new account *every* tab is empty at
/// once, so that instruction was the entire first-run experience. Routing
/// through shared state (rather than each view owning a tab binding) keeps
/// the handoff to one call: `navigation.startAddingProduct()`.
@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .routine

    /// Set when another tab has asked for the add-product sheet. The
    /// Cabinet tab consumes and clears it once presented -- a one-shot
    /// signal, not a piece of durable state.
    var isAddingProduct = false

    /// Switch to the Cabinet and open its add-product sheet.
    func startAddingProduct() {
        selectedTab = .cabinet
        isAddingProduct = true
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
    }
}
