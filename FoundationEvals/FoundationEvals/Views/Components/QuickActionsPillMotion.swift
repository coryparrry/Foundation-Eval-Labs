import SwiftUI

/// Every animation the pill runs, as named tokens on one scale.
///
/// Content swapping in place rides `easeOut`; everything that moves *within*
/// the pill while staying on screen rides `easeInOut`.
struct QuickActionsPillMotion {
    /// The strong ease-out for content arriving in place.
    ///
    /// SwiftUI's built-in `.easeOut` is far too weak to read as deliberate at
    /// these durations — it leaves motion looking like it drifted to a stop
    /// rather than arrived.
    private static func easeOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// The strong ease-in-out, for something already on screen changing shape.
    ///
    /// Symmetric because a morph has no arrival and no departure — the capsule
    /// is present at both ends, and easing only one side would make it look
    /// like it was being pushed rather than changing.
    private static func easeInOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duration)
    }

    /// The capsule's width interpolating between phases.
    var morph: Animation { Self.easeInOut(0.24) }

    /// The action row swapping between compact and expanded.
    var menuSwap: Animation { Self.easeInOut(0.24) }

    /// One phase's controls crossfading out as the next crossfades in.
    ///
    /// Deliberately shorter than `morph`: the content should have settled by
    /// the time the capsule finishes resizing, or the user reads text that is
    /// still sliding.
    var content: Animation { Self.easeOut(0.18) }

    /// Press feedback. At the bottom of the 100-160ms budget because a button
    /// is the most-touched thing here and anything slower feels like lag.
    var press: Animation { Self.easeOut(0.12) }
}

struct QuickActionsPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            // Never scale from zero, and never far: 0.97 is enough to feel
            // under the pointer and small enough that a mis-click does not
            // look like a glitch.
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(QuickActionsPillMotion().press, value: configuration.isPressed)
    }
}
