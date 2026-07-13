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

    public init(image: NSImage, width: CGFloat, height: CGFloat) {
        self.image = image
        self.width = width
        self.height = height
    }

    public var body: some View {
        base
            .overlay(
                shimmerOverlay
                    .mask(base)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onAppear { scheduleNext() }
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

    /// Schedule the next sweep at a random, rare interval so it feels organic.
    private func scheduleNext() {
        let delay = Double.random(in: 6.0...14.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            triggerSweep()
            scheduleNext()
        }
    }

    private func triggerSweep() {
        phase = 0
        shimmering = true
        withAnimation(.easeInOut(duration: 1.15)) {
            phase = 1
        }
        // Fade the band out just after it clears the right edge.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) { shimmering = false }
        }
    }
}
