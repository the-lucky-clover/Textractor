import SwiftUI

// MARK: - BreakingDad Palette
// Toxic lab green, blue-crystal, and hazmat yellow on greenish-black. This is the
// single source of truth for the Breaking Dad HUD aesthetic (replaces NeonTheme).

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

    /// Toxic-green -> hazmat-yellow sweep for accented borders.
    public static let gradient = LinearGradient(
        gradient: Gradient(colors: [toxicGreen, hazmatYellow]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - BreakingDad Theme
//
// Breaking-Bad-inspired HUD styling for the Settings window: chemistry-lab
// toxic green, blue-crystal, and hazmat yellow on a greenish-black backdrop.
// Uses the `BreakingDad` palette (defined above) and the shared
// `textractorHeaderBackground` so the Settings window feels like the same
// surface as the menubar popover.

public enum BreakingDadFont {
    /// Condensed, industrial-feeling label — heavy weight, slightly tracked.
    public static func hudTitle(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }
    public static func hudHead(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    public static func hudMono(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
    public static func hudCaps(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .black, design: .monospaced).smallCaps()
    }
}

public extension Color {
    /// Shared dark backdrop identical to the menubar popover.
    static var breakingDadBackdrop: Color { textractorHeaderBackground }
}

// MARK: - HUD card

/// A compact, lab-instrument style panel: greenish-black fill, thin toxic-green
/// hairline border, subtle inner glow. Replaces the neon glass cards.
public struct BreakingDadCard<Content: View>: View {
    var title: String
    var icon: String
    var accent: Color
    @ViewBuilder var content: () -> Content

    public init(
        title: String,
        icon: String,
        accent: Color = BreakingDad.toxicGreen,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(BreakingDadFont.hudCaps(10))
                    .foregroundStyle(BreakingDad.chalk.opacity(0.92))
                    .tracking(1.2)
                Spacer()
            }
            content()
                .padding(.horizontal, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BreakingDad.deepGreen.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.55), lineWidth: 1)
        )
    }
}

// MARK: - HUD accent button

/// Small pill button used for secondary actions (e.g. "Choose…", "Reset").
public struct BreakingDadButton: View {
    var title: String
    var icon: String? = nil
    var tint: Color
    var action: () -> Void

    public init(_ title: String, icon: String? = nil, tint: Color = BreakingDad.toxicGreen, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(BreakingDadFont.hudCaps(10))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 0.8))
            )
        }
        .buttonStyle(.plain)
    }
}
