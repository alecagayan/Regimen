//
//  NetworkMonitor.swift
//  Regimen
//

import Foundation
import Network

/// Publishes whether the device currently has a usable network path.
///
/// Used only to *explain* things to the user -- an offline banner, and
/// wording on a failed action -- never to decide whether to attempt a
/// request. `NWPathMonitor` reports the local interface's state, which is
/// not the same as "Supabase is reachable": captive portals, DNS failures
/// and server outages all report `.satisfied`. So the app always tries the
/// request and lets it fail honestly; this just lets the failure say
/// "you're offline" instead of something vaguer when that's the likely
/// cause.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Starts optimistic: assuming offline before the first path update
    /// arrives would flash a banner on every cold launch.
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
