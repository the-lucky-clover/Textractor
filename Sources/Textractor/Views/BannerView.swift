import SwiftUI
import AppKit

/// Shared header background for the menubar popover and Settings — R:13 G:16 B:11.
public let textractorHeaderBackground = Color(
    red: 13.0 / 255.0,
    green: 16.0 / 255.0,
    blue: 11.0 / 255.0
)

/// Resolves the wordmark banner image from the app bundle. Distributed
/// builds copy `textractor-type.png` into `Contents/Resources` via `build.sh`
/// and `Bundle.main.url(forResource:withExtension:)` finds it there. When
/// running outside a bundle (e.g. raw `swift build` during development) the
/// helper returns `nil` so the rest of the UI degrades gracefully.
public func loadBannerImage() -> NSImage? {
    if let url = Bundle.main.url(forResource: "textractor-type", withExtension: "png"),
       let img = NSImage(contentsOf: url) {
        return img
    }
    #if SWIFT_PACKAGE
    if let url = Bundle.module.url(forResource: "textractor-type", withExtension: "png") {
        return NSImage(contentsOf: url)
    }
    #endif
    return nil
}

/// The wordmark banner with a **rare, intermittent** photorealistic specular
/// shimmer — a soft, blurred glint that sweeps diagonally across the logo every
/// several seconds (randomised), masked to the logo pixels and composited with a
/// screen blend so it reads like real light catching the surface.
public struct ShimmerBanner: View {
    let image: NSImage
    let width: CGFloat
    let height: CGFloat

    /// Sweep position: 0 = fully off the left edge, 1 = fully off the right.
    @State private var phase: CGFloat = 0
    @State private var shimmering: Bool = false

    /// When `false`, the specular sweep is skipped (reduce-motion / calm UI).
    public var animate: Bool = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(image: NSImage, width: CGFloat, height: CGFloat, animate: Bool = true) {
        self.image = image
        self.width = width
        self.height = height
        self.animate = animate
    }

    public var body: some View {
        base
            .overlay(
                shimmerOverlay
                    .mask(base)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: animate && !systemReduceMotion) {
                shimmering = false
                guard animate && !systemReduceMotion else { return }
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(Double.random(in: 6...14)))
                        try Task.checkCancellation()
                        phase = 0
                        shimmering = true
                        withAnimation(.easeInOut(duration: 1.15)) { phase = 1 }
                        try await Task.sleep(for: .seconds(1.2))
                        shimmering = false
                    } catch { return }
                }
            }
    }

    private var base: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
    }

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let band = max(w * 0.16, 26)
            LinearGradient(
                stops: [
                    .init(color: .clear,                location: 0.00),
                    .init(color: .white.opacity(0.10),  location: 0.42),
                    .init(color: .white.opacity(0.95),  location: 0.50),
                    .init(color: .white.opacity(0.10),  location: 0.58),
                    .init(color: .clear,                location: 1.00),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band, height: h * 2.2)
            .blur(radius: 5)
            .rotationEffect(.degrees(20))
            .offset(x: -band + phase * (w + band * 2), y: -h * 0.6)
            .blendMode(.screen)
            .opacity(shimmering ? 1 : 0)
        }
    }

 }

/// Both existing header widths share the same inset, wordmark and embossed Pro badge.
struct ProductBanner: View {
    let width: CGFloat
    let animate: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if let image = loadBannerImage() {
                    ShimmerBanner(image: image, width: width - 68, height: 62, animate: animate)
                        .accessibilityHidden(true)
                } else {
                    Text("Textractor").font(.title3.bold()).foregroundStyle(BreakingDad.chalk)
                }
                Text("PRO")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(BreakingDad.chalk)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(BreakingDad.deepGreen))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(BreakingDad.toxicGreen.opacity(0.55)))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            }
            .frame(width: width, height: 76)
            Rectangle().fill(BreakingDad.gradient).frame(height: 1).opacity(0.35)
        }
        .frame(width: width)
        .clipped()
        // Decorative shimmer geometry must not obscure nearby controls in
        // accessibility hit testing, even when its pixels are clipped.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
