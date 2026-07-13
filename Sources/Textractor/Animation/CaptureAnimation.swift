import SwiftUI

/// A collection of reusable animation sequences.
struct CaptureAnimation {
    /// A smooth reveal for the popover container on first launch.
    static let revealPopover = Animation
        .linear(duration: 1.5)

    /// A slow neon-glow pulse (breathing effect) used on icons and text.
    static let neonPulse = Animation
        .timingCurve(0.4, 0, 0.2, 1, duration: 2.0)
        .repeatForever(autoreverses: true)

    /// A spring-style overshoot used for dropdowns or menu items.
    static let knuckleheadFall = Animation
        .interpolatingSpring(stiffness: 120, damping: 10)

    /// Fades a view in while simultaneously scaling up slightly.
    static let fadeInAndPop = Animation
        .easeInOut(duration: 0.6)
        .delay(0.1)

    /// Used for section headers when tapped – a tiny scale & color flash.
    static let sectionTap = Animation
        .interactiveSpring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)
}
