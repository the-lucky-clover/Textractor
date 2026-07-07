//
//  TextractorTheme.swift
//  Textractor
//
//  Blade Runner 2049 × Cyberpunk 2077 design system.
//  Neon-glowing, glassmorphic, bento-box, optically-soothing.
//

import SwiftUI

// MARK: - Color Palette

extension Color {
    // Primary neon accents
    static let neonCyan     = Color(red: 0.0, green: 0.92, blue: 1.0)      // #00EAFF — Tron / BR2049
    static let neonMagenta  = Color(red: 0.95, green: 0.0, blue: 0.78)     // #F200C7 — Cyberpunk
    static let neonAmber    = Color(red: 1.0, green: 0.72, blue: 0.12)     // #FFB81F — BR2049 amber
    static let neonPurple   = Color(red: 0.55, green: 0.24, blue: 0.97)    // #8C3DF8 — Cyberpunk
    static let neonGreen    = Color(red: 0.0, green: 1.0, blue: 0.55)      // #00FF8C — Matrix
    static let neonRed      = Color(red: 1.0, green: 0.18, blue: 0.28)     // #FF2E47 — Alert
    static let neonPink     = Color(red: 1.0, green: 0.32, blue: 0.62)     // #FF52A0
    static let neonGray     = Color(red: 0.45, green: 0.48, blue: 0.55)

    // Deep backgrounds — the rain-slicked neon city night
    static let deepVoid     = Color(red: 0.025, green: 0.028, blue: 0.045) // near-black indigo
    static let deepPanel    = Color(red: 0.045, green: 0.05, blue: 0.085)
    static let deepGlass    = Color(red: 0.06, green: 0.075, blue: 0.115)
    static let deepSurface  = Color(red: 0.08, green: 0.095, blue: 0.14)
}

// MARK: - Gradients

enum TextractorGradient {
    static let primaryGlow = LinearGradient(
        colors: [.neonCyan, .neonMagenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let amberHorizon = LinearGradient(
        colors: [.neonAmber.opacity(0.9), .neonRed.opacity(0.7)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cyberpunkSky = LinearGradient(
        colors: [.neonPurple.opacity(0.3), .neonMagenta.opacity(0.2), .neonCyan.opacity(0.15)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let scanningLine = LinearGradient(
        colors: [.clear, .neonCyan.opacity(0.9), .neonCyan, .neonCyan.opacity(0.9), .clear],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let voidBackground = LinearGradient(
        colors: [.deepVoid, .deepPanel, .deepVoid],
        startPoint: .top,
        endPoint: .bottom
    )

    static let panelEdge = LinearGradient(
        colors: [.neonCyan.opacity(0.5), .neonMagenta.opacity(0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Shadows & Glows

enum TextractorGlow {
    static func cyan(_ radius: CGFloat = 8) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (.neonCyan, radius, 0, 0)
    }
    static func magenta(_ radius: CGFloat = 8) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (.neonMagenta, radius, 0, 0)
    }
    static func amber(_ radius: CGFloat = 8) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (.neonAmber, radius, 0, 0)
    }
    static func green(_ radius: CGFloat = 8) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (.neonGreen, radius, 0, 0)
    }
}

// MARK: - Typography

enum TextractorFont {
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Metrics

enum TextractorMetrics {
    static let cornerRadiusL:   CGFloat = 20
    static let cornerRadiusM:   CGFloat = 14
    static let cornerRadiusS:   CGFloat = 10
    static let cornerRadiusXS:  CGFloat = 6
    static let paddingL:        CGFloat = 24
    static let paddingM:        CGFloat = 16
    static let paddingS:        CGFloat = 10
    static let paddingXS:       CGFloat = 6
    static let glassBlur:       CGFloat = 40
    static let popoverWidth:    CGFloat = 380
    static let popoverHeight:   CGFloat = 520
    static let overlayInset:    CGFloat = 2
}

// MARK: - View Modifiers

struct GlassMorphism: ViewModifier {
    var cornerRadius: CGFloat = TextractorMetrics.cornerRadiusM
    var opacity: Double = 0.06
    var borderOpacity: Double = 0.15

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity + 0.55)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.deepGlass)
                    .opacity(opacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        TextractorGradient.panelEdge,
                        lineWidth: 0.5
                    )
                    .opacity(borderOpacity)
            )
            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 6)
    }
}

// (NeonGlow ViewModifier lives in NeonTheme.swift as Public NeonGlow enum;
//  this file contributes Color/Neon naming only.)

struct ScanlineOverlay: ViewModifier {
    var opacity: Double = 0.03

    func body(content: Content) -> some View {
        content.overlay(
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.neonCyan.opacity(opacity))
                    )
                    y += 3
                }
            }
            .allowsHitTesting(false)
        )
    }
}

extension View {
    // (NeonGlow-based modifier is provided by NeonTheme.NeonGlow.outer(...) / .inner(...))

    func scanlines(_ opacity: Double = 0.03) -> some View {
        modifier(ScanlineOverlay(opacity: opacity))
    }
}

// MARK: - Hover Glow Modifier (placeholder hook)

struct HoverGlowModifier: ViewModifier {
    var color: Color = .neonCyan

    func body(content: Content) -> some View {
        content
            .onHover { _ in }
    }
}

extension View {
    func hoverGlow(color: Color = .neonCyan) -> some View {
        modifier(HoverGlowModifier(color: color))
    }
}
