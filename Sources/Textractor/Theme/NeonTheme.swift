import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Neon Palette
// Blade Runner 2049 × Cyberpunk 2077 — high-contrast cyberpunk noir.
// All colors are defined in HSB or sRGB so they remain consistent w/ dark & light.

public enum NeonPalette {
    // Base backdrop — deep noir
    public static let noir         = Color(red: 0.040, green: 0.045, blue: 0.095) // #0A0B18
    public static let noirDeep     = Color(red: 0.020, green: 0.025, blue: 0.060) // #05060F
    public static let carbon       = Color(red: 0.08,  green: 0.09,  blue: 0.16)  // #151728

    // Cyberpunk primary neon
    public static let cyberCyan    = Color(red: 0.215, green: 0.949, blue: 1.0)   // #37F2FF
    public static let magentaNeon  = Color(red: 1.000, green: 0.239, blue: 0.804) // #FF3DCD
    public static let acidLime     = Color(red: 0.616, green: 1.000, blue: 0.259) // #9DFF42
    public static let amberLaser   = Color(red: 1.000, green: 0.643, blue: 0.114) // #FFA41D
    public static let hazardRed    = Color(red: 1.000, green: 0.184, blue: 0.298) // #FF2F4C
    public static let holoViolet   = Color(red: 0.620, green: 0.357, blue: 1.000) // #9E5BFF

    // Surfaces (translucent glass + neumorphic)
    public static let glass        = Color.white.opacity(0.04)
    public static let glassHeavy   = Color.white.opacity(0.08)
    public static let glassWhite   = Color.white.opacity(0.12)
    public static let inkHigh      = Color.white.opacity(0.95)
    public static let inkMid       = Color.white.opacity(0.65)
    public static let inkLow       = Color.white.opacity(0.45)

    // Sentiment-driven accents (used by toast / analysis chips)
    public static func sentiment(_ polarity: Double) -> Color {
        if polarity >  0.15 { return acidLime }
        if polarity < -0.15 { return hazardRed }
        return                      cyberCyan
    }

    /// Linear gradient sweep — magenta → cyan → violet — used on bento card borders.
    public static let gradientPrimary = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: magentaNeon, location: 0.0),
            .init(color: cyberCyan,   location: 0.55),
            .init(color: holoViolet,  location: 1.0),
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle scan-line overlay
    public static let scanlines = LinearGradient(
        gradient: Gradient(colors: [
            .clear,
            Color.white.opacity(0.04),
            .clear,
            Color.white.opacity(0.02),
            .clear
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - BreakingDad Palette
// Toxic lab green, blue-crystal, and hazmat yellow on greenish-black. Used for
// the capture overlay (window highlight glow, accents).

public enum BreakingDad {
    /// Signature chemistry / toxic lab green.
    public static let toxicGreen    = Color(red: 0.42, green: 0.71, blue: 0.20) // #6BB534
    /// Deeper money/lab green for fills and shadows.
    public static let deepGreen     = Color(red: 0.18, green: 0.36, blue: 0.11) // #2E5C1C
    /// Blue-crystal (the famous product) — cool cyan-blue accent.
    public static let methBlue      = Color(red: 0.16, green: 0.67, blue: 0.88) // #29ABE0
    /// Hazmat suit yellow.
    public static let hazmatYellow  = Color(red: 0.96, green: 0.78, blue: 0.08) // #F5C714
    /// Caution / barrel orange.
    public static let cautionOrange = Color(red: 0.90, green: 0.45, blue: 0.13) // #E67321
    /// Danger rust red.
    public static let rust          = Color(red: 0.72, green: 0.16, blue: 0.12) // #B8291F
    /// Off-white chalk for faint outlines / neutral ink.
    public static let chalk         = Color(red: 0.90, green: 0.92, blue: 0.86) // #E6EADC
    /// Greenish near-black backdrop.
    public static let greenBlack    = Color(red: 0.043, green: 0.063, blue: 0.039) // #0B100A

    /// Toxic-green → hazmat-yellow sweep for accented borders.
    public static let gradient = LinearGradient(
        gradient: Gradient(colors: [toxicGreen, hazmatYellow]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}


// MARK: - Gradients as ShapeStyles (for SwiftUI `foregroundStyle` etc)
public struct NeonGradientStyle: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        ZStack {
            NeonPalette.gradientPrimary
                .mask(content)
        }
    }
}

public extension View {
    /// Apply the neon primary gradient as a foreground mask over `self`.
    func neonGradientMask() -> some View {
        modifier(NeonGradientStyle())
    }
}

// MARK: - Shadows & glows
public enum NeonGlow {
    /// Outer glow with strong neon color (used on the crosshair handle)
    public static func outer(_ color: Color, radius: CGFloat = 18, opacity: Double = 0.55) -> some ViewModifier {
        return VisualEffectShadow(color: color, radius: radius, opacity: opacity, isInner: false)
    }

    /// Inner hover-glow (used on bento card hover-state)
    public static func inner(_ color: Color, radius: CGFloat = 12, opacity: Double = 0.45) -> some ViewModifier {
        return VisualEffectShadow(color: color, radius: radius, opacity: opacity, isInner: true)
    }
}

private struct VisualEffectShadow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let opacity: Double
    let isInner: Bool

    func body(content: Content) -> some View {
        if isInner {
            content
                .shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
                .shadow(color: color.opacity(opacity * 0.4), radius: radius * 0.5, x: 0, y: 0)
        } else {
            content
                .shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
                .shadow(color: color.opacity(opacity * 0.5), radius: radius * 0.6, x: 0, y: 0)
        }
    }
}

// MARK: - Typography
public enum NeonFont {
    public static func roundedTitle(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    public static func roundedHeadline(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func mono(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    public static func monoCaps(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .black, design: .monospaced)
    }
}

// MARK: - Motion Tokens
public enum Motion {
    public static let springTactile: Animation = .spring(response: 0.36, dampingFraction: 0.62, blendDuration: 0.18)
    public static let springFloaty:  Animation = .spring(response: 0.55, dampingFraction: 0.78)
    public static let easeOutSnappy: Animation = .easeOut(duration: 0.22)
    public static let easeInOutSoft: Animation = .easeInOut(duration: 0.45)
}

// MARK: - Corner Radii (matches SwiftUI Apple HIG with cyberpunk bend)
public enum Radius {
    public static let sm:  CGFloat = 10
    public static let md:  CGFloat = 18
    public static let lg:  CGFloat = 26
    public static let xl:  CGFloat = 34
}
