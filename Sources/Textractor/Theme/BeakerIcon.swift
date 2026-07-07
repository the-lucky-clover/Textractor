import SwiftUI

// MARK: - BeakerIcon
//
// Vector silhouette of a chemistry round-bottom flask full of letters.
// Matches the App Store icon aesthetic — glass flask, glowing teal liquid,
// floating typography ("T", "X", "T") inside the belly.
//
// Two presentation modes:
//   • `.neon`     — full cyan/magenta branding (used in menu window & bento hero)
//   • `.template` — monochrome silhouette using `.primary` so it adapts to the
//                  dark/light menu bar (used in the macOS menubar label)
//
// The icon is a composition of:
//   • Anti-aliased stroked primitives (cap, neck, bulb)
//   • A radial-gradient liquid fill inside the bulb (clipped by the bulb path)
//   • 1–3 small "floating letter" glyphs inside the liquid
//   • An optional meniscus ellipse for a hint of "chemistry"
//
public struct BeakerIcon: View {

    public enum Style { case neon, template }

    public var size: CGFloat
    public var liquidColor: Color
    public var strokeColor: Color?
    public var glyphs: [String]
    public var style: Style
    public var showLiquid: Bool
    public var showLetterGlow: Bool

    public init(
        size: CGFloat = 22,
        glyphs: [String] = ["T", "X", "T"],
        liquidColor: Color = NeonPalette.cyberCyan,
        strokeColor: Color? = nil,
        style: Style = .neon,
        showLiquid: Bool = true,
        showLetterGlow: Bool = true
    ) {
        self.size = size
        self.glyphs = glyphs
        self.liquidColor = liquidColor
        self.strokeColor = strokeColor
        self.style = style
        self.showLiquid = showLiquid
        self.showLetterGlow = showLetterGlow
    }

    // MARK: Resolved colors per style

    private var primaryInk: Color {
        style == .template ? .primary : (strokeColor ?? liquidColor)
    }

    private var liquidTopColor: Color {
        style == .template ? .primary.opacity(0.35) : liquidColor.opacity(0.85)
    }

    private var liquidMidColor: Color {
        style == .template ? .primary.opacity(0.18) : liquidColor.opacity(0.30)
    }

    private var letterTint: Color {
        style == .template ? .primary : liquidColor
    }

    private var strokeWidth: CGFloat { max(1.0, size * 0.075) }

    // MARK: Layout (all in points relative to a `size` × `size` square)
    // Bulb circle sits low, neck rises out of it, cap seals the top.

    private var bulbDiameter: CGFloat { size * 0.96 }
    private var bulbOffsetY: CGFloat { size * 0.07 }
    private var neckWidth: CGFloat { size * 0.22 }
    private var neckHeight: CGFloat { size * 0.30 }
    private var neckOffsetY: CGFloat { -size * 0.27 }
    private var capWidth: CGFloat { size * 0.36 }
    private var capHeight: CGFloat { size * 0.05 }
    private var capOffsetY: CGFloat { -size * 0.44 }
    private var meniscusYOffset: CGFloat { -size * 0.10 }

    // Letter density — at very small sizes, drop to a single big "T" so it
    // stays legible in the menubar.
    private var visibleGlyphs: [String] {
        size < 28 ? Array(glyphs.prefix(1)) : glyphs
    }

    // MARK: Body

    public var body: some View {
        ZStack {
            liquidFill
            floatingLetters
            meniscusEllipse
            flaskOutline
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Textractor")
        .accessibilityHidden(false)
    }

    // Bulb fill — radial gradient clipped to circle
    private var liquidFill: some View {
        Group {
            if showLiquid {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                liquidTopColor,
                                liquidMidColor,
                                .clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: bulbDiameter * 0.55
                        )
                    )
                    .frame(width: bulbDiameter, height: bulbDiameter)
                    .offset(y: bulbOffsetY)
            }
        }
    }

    // Optional small meniscus highlight (chemistry flask "lip" of liquid)
    private var meniscusEllipse: some View {
        Group {
            if showLiquid && style == .neon {
                Ellipse()
                    .stroke(primaryInk.opacity(0.55), lineWidth: max(0.5, strokeWidth * 0.5))
                    .frame(width: size * 0.50, height: size * 0.08)
                    .offset(y: meniscusYOffset)
            }
        }
    }

    // Foreground letters floating inside the bulb
    private var floatingLetters: some View {
        Group {
            if style == .neon {
                if visibleGlyphs.count > 0 {
                    FloatingLetter(
                        glyph: visibleGlyphs[0],
                        size: size,
                        color: letterTint,
                        x: -0.13, y: 0.30,
                        rotation: -8, scale: 0.78,
                        glow: showLetterGlow,
                        opacity: 0.92
                    )
                }
                if visibleGlyphs.count > 1 {
                    FloatingLetter(
                        glyph: visibleGlyphs[1],
                        size: size,
                        color: letterTint,
                        x: 0.14, y: 0.44,
                        rotation: 6, scale: 0.85,
                        glow: showLetterGlow,
                        opacity: 0.92
                    )
                }
                if visibleGlyphs.count > 2 {
                    FloatingLetter(
                        glyph: visibleGlyphs[2],
                        size: size,
                        color: letterTint,
                        x: 0.02, y: 0.58,
                        rotation: -2, scale: 0.74,
                        glow: showLetterGlow,
                        opacity: 0.92
                    )
                }
            } else {
                // Template variant: a single prominent letter for branding
                if visibleGlyphs.count > 0 {
                    FloatingLetter(
                        glyph: visibleGlyphs[0],
                        size: size,
                        color: letterTint,
                        x: 0, y: 0.45,
                        rotation: 0, scale: 1.0,
                        glow: false,
                        opacity: 0.85
                    )
                }
            }
        }
    }

    // The flask silhouette — three stroked primitives composed in ZStack
    private var flaskOutline: some View {
        ZStack {
            // Cap (flat lip on top)
            Capsule()
                .stroke(primaryInk, lineWidth: strokeWidth)
                .frame(width: capWidth, height: capHeight)
                .offset(y: capOffsetY)

            // Neck (rounded rect)
            RoundedRectangle(cornerRadius: size * 0.04)
                .stroke(primaryInk, lineWidth: strokeWidth)
                .frame(width: neckWidth, height: neckHeight)
                .offset(y: neckOffsetY)

            // Bulb (round-bottom flask belly)
            Circle()
                .stroke(primaryInk, lineWidth: strokeWidth)
                .frame(width: bulbDiameter, height: bulbDiameter)
                .offset(y: bulbOffsetY)
        }
    }
}

// MARK: - Single floating letter inside the flask
private struct FloatingLetter: View {
    var glyph: String
    var size: CGFloat
    var color: Color
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var glow: Bool
    var opacity: Double

    var body: some View {
        Text(glyph)
            .font(.system(
                size: size * 0.36 * scale,
                weight: .heavy,
                design: .rounded
            ))
            .foregroundStyle(color.opacity(opacity))
            .rotationEffect(.degrees(rotation))
            .offset(x: size * x, y: size * y)
            .shadow(color: glow ? color.opacity(0.65) : .clear, radius: size * 0.07)
    }
}

// MARK: - BeakerIcon convenience initializers
public extension BeakerIcon {
    /// Compact menubar variant — small monochrome silhouette with one bold "T".
    static func menubar(size: CGFloat = 22) -> BeakerIcon {
        BeakerIcon(
            size: size,
            glyphs: ["T"],
            style: .template,
            showLiquid: true,
            showLetterGlow: false
        )
    }

    /// Branded hero variant — use in the flair/bento-window hero card.
    static func hero(size: CGFloat = 120) -> BeakerIcon {
        BeakerIcon(
            size: size,
            glyphs: ["T", "X", "T"],
            style: .neon,
            showLiquid: true,
            showLetterGlow: true
        )
    }

    /// Mini badge variant — small neon icon with the full "TXT" letter trio.
    static func badge(size: CGFloat = 36) -> BeakerIcon {
        BeakerIcon(
            size: size,
            glyphs: ["T", "X", "T"],
            style: .neon,
            showLiquid: true,
            showLetterGlow: true
        )
    }
}

// MARK: - NSImage bridge (for funcs that need raster output, e.g. async image)
public extension BeakerIcon {
    /// Raster this SwiftUI view into an NSImage at 2x scale (template-adjusted).
    @MainActor
    func renderImage(forStyleOnDarkBar: Bool = true) -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2.0
        if let cg = renderer.cgImage {
            let img = NSImage(cgImage: cg, size: NSSize(width: size, height: size))
            img.isTemplate = style == .template
            return img
        }
        return nil
    }
}
