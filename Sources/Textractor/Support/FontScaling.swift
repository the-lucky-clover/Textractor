import SwiftUI

/// A key for storing the current font scale factor in the SwiftUI environment.
/// Defaults to 1.0 (standard size).
private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    /// The current font scale factor for accessibility text size adjustment.
    /// Clamped to a reasonable range (0.75–2.5) by the settings store.
    var fontScale: Double {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

/// A view modifier that applies the current font scale to all text within the view.
/// Use `.fontScaled()` on the root view of a window/popover to propagate the scale.
private struct FontScaledModifier: ViewModifier {
    @Environment(\.fontScale) private var scale

    func body(content: Content) -> some View {
        content
            .environment(\.fontScale, scale)
    }
}

extension View {
    /// Applies font scaling to all text within this view hierarchy.
    /// Call this on the root view of each window/popover/content view.
    func fontScaled(_ scale: Double? = nil) -> some View {
        if let scale {
            return AnyView(self.environment(\.fontScale, scale))
        }
        return AnyView(self.modifier(FontScaledModifier()))
    }
}

/// A font wrapper that automatically applies the current font scale.
/// Usage: `Font.scaled(size: 13, weight: .regular, design: .default)`
extension Font {
    static func scaled(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        // Note: This initializer doesn't have access to environment values.
        // Use the `.appFont()` view modifier below instead for environment-aware scaling.
        .system(size: size, weight: weight, design: design)
    }
}

/// A view modifier that scales the font of `Text` views based on the current `fontScale` environment value.
/// Apply with `.appFont(size: 13, weight: .regular, design: .default)` instead of `.font(...)`.
private struct AppFontModifier: ViewModifier {
    @Environment(\.fontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// Scales the font based on the current `fontScale` environment value.
    /// Use this instead of `.font(.system(...))` for text that should respect accessibility settings.
    func appFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, design: design))
    }
}