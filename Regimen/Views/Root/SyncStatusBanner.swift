//
//  SyncStatusBanner.swift
//  Regimen
//

import SwiftUI

/// A thin status strip for the three states where the app knows something
/// the user doesn't: no network, work not yet uploaded, or stale data on
/// screen because a fetch failed.
///
/// Previously all three were invisible. Offline, the app looked identical
/// to online; a check-off that never reached the server looked identical to
/// one that did. For a streak the user is trying to protect, "we've got
/// this, it just hasn't uploaded yet" is worth a line of text.
struct SyncStatusBanner: View {
    let isOnline: Bool
    let hasUnsyncedChanges: Bool
    let isShowingCachedData: Bool
    /// Whether a fetch is in flight. `AppData.isLoading` existed but was
    /// read by exactly zero views, so a cold launch showed cached data with
    /// no sign that anything was refreshing behind it.
    var isLoading: Bool = false

    private var state: State? {
        // Only while there's stale data on screen -- a spinner over a
        // first-ever load is already covered by `RootView`'s loading view,
        // and announcing every background refresh would make the banner
        // flicker on every foreground.
        if isLoading && isShowingCachedData {
            return State(icon: "arrow.triangle.2.circlepath", message: "Refreshing…", tint: .secondary)
        }
        if !isOnline {
            return State(
                icon: "wifi.slash",
                message: hasUnsyncedChanges
                    ? "Offline. Your changes are saved and will sync later."
                    : "Offline. Showing your saved routine.",
                tint: .orange
            )
        }
        if hasUnsyncedChanges {
            return State(icon: "arrow.triangle.2.circlepath", message: "Syncing your changes…", tint: .orange)
        }
        if isShowingCachedData {
            return State(icon: "exclamationmark.icloud", message: "Couldn't reach the server. Showing saved data.", tint: .orange)
        }
        return nil
    }

    private struct State {
        let icon: String
        let message: String
        let tint: Color
    }

    var body: some View {
        if let state {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: state.icon)
                    .font(.caption.weight(.semibold))
                Text(state.message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(state.tint)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(state.tint.opacity(0.12))
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}
