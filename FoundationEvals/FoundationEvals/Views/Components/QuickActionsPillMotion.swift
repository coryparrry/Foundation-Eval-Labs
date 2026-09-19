import SwiftUI

struct QuickActionsPillMotion {
    private static func easeOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    private static func easeInOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duration)
    }

    var morph: Animation { Self.easeInOut(0.24) }
    var menuSwap: Animation { Self.easeInOut(0.24) }
    var content: Animation { Self.easeOut(0.18) }
    var press: Animation { Self.easeOut(0.12) }
}

struct QuickActionsPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(QuickActionsPillMotion().press, value: configuration.isPressed)
    }
}
