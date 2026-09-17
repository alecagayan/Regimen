//
//  Motion.swift
//  Regimen
//

import SwiftUI

/// The app's animation vocabulary, in one place for the same reason
/// `Theme` holds spacing and radii: a dozen views each inventing their own
/// spring is how an interface ends up feeling subtly inconsistent without
/// anyone being able to point at why.
///
/// Every curve here is short. This is a utility people open twice a day at
/// a bathroom sink, not something to sit and admire -- animation's job is
/// to explain what changed, and anything long enough to notice as an
/// animation is too long.
enum Motion {
    /// Toggling something on or off. The snappiest curve here, because it
    /// answers a tap and any delay reads as lag.
    static let toggle = Animation.spring(response: 0.28, dampingFraction: 0.7)

    /// A value sliding to a new position: progress bars, gauges.
    static let value = Animation.easeOut(duration: 0.45)

    /// Cards and banners arriving or leaving.
    static let card = Animation.spring(response: 0.38, dampingFraction: 0.82)

    /// The score counting up after a scan. Slow enough to read as a
    /// deliberate reveal, since it's the one number the user waited on.
    static let reveal = Animation.easeOut(duration: 0.9)

    /// Staggered delay for the nth item in a sequenced reveal, capped so a
    /// long list never leaves the last card waiting.
    static func stagger(_ index: Int, step: Double = 0.06, cap: Double = 0.4) -> Double {
        min(Double(index) * step, cap)
    }
}

extension View {
    /// Applies an animation unless the reader has asked the system for
    /// less motion, in which case the change is instant.
    ///
    /// Reduce Motion is a real accessibility setting, not a preference to
    /// pay lip service to: for some people motion on screen causes actual
    /// nausea. Everything in this app that moves goes through here, so the
    /// setting is honoured in one place rather than remembered view by view.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// One card in a sequenced reveal. Fades and settles into place, offset
    /// by its position so a screen of results arrives in reading order
    /// instead of landing in a single frame.
    ///
    /// The scan results are four cards that all become available at the
    /// same instant, and showing them simultaneously makes a considered
    /// analysis look like a dump. Ordering the arrival is the difference
    /// between "here is everything" and "here is what I found, then what
    /// that means".
    func sequencedReveal(_ index: Int, trigger: Bool) -> some View {
        transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            .motion(Motion.card.delay(Motion.stagger(index)), value: trigger)
    }
}

/// A number that animates between values rather than cutting to the new
/// one.
///
/// `Animatable` interpolates `animatableData` frame by frame, so the body
/// re-renders with every intermediate value -- which is what produces a
/// count-up rather than a cross-fade between two final numbers.
struct AnimatedNumber: View, Animatable {
    var value: Double
    var font: Font = .metricLarge
    var color: Color = .brand

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
            .font(font)
            .foregroundStyle(color)
            // Digits are proportionally spaced by default, so a counter
            // passing through 8 -> 11 -> 74 visibly jitters its own width
            // and shoves whatever sits beside it.
            .monospacedDigit()
            .contentTransition(.identity)
    }
}
