//
//  MLModelConfiguration+AppDefault.swift
//  Regimen
//

import CoreML

extension MLModelConfiguration {
    /// The Simulator's GPU/Neural Engine emulation for Core ML has real,
    /// observed reliability gaps ("MpsGraph backend validation on
    /// incompatible OS", "Espresso compiled without MPSGraph engine") that
    /// don't reflect how these models behave on a real device -- so every
    /// on-device model load in this app forces CPU-only when running in
    /// the Simulator, and leaves full GPU/Neural Engine performance alone
    /// on real hardware.
    static var appDefault: MLModelConfiguration {
        let configuration = MLModelConfiguration()
        #if targetEnvironment(simulator)
        configuration.computeUnits = .cpuOnly
        #endif
        return configuration
    }
}
