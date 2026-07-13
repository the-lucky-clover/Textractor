import SwiftUI

/// Matrix-rain backdrop. Drops random glyphs (kana + kanji + ASCII) in
/// vertical columns from top to bottom. Columns carry per-column "depth"
/// that scales speed, brightness, and horizontal jitter for a parallax /
/// pseudo-3D effect against a pure-black canvas.
///
/// Animation is driven by `TimelineView(.animation)`. Per-column state is
/// seeded once and is fully deterministic — re-laying out the view doesn't
/// reshuffle the falling glyphs.
struct MatrixRainView: View {

    /// 0.0 → invisible, 1.0 → fully on. Drives the animated fade in / out.
    var opacity: Double

    private let glyphs: [Character] =
        Array("日月火水木金土山川田人口")
        + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        + Array("0123456789")

    private let columnWidth: CGFloat = 16
    private let rowHeight: CGFloat = 18

    @State private var streams: [MatrixRainView.Stream] = []

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let columns = max(8, Int(size.width / columnWidth))
            let rows = max(8, Int(size.height / rowHeight))
            TimelineView(.animation) { context in
                Canvas { gc, _ in
                    // Black background so the greens pop.
                    gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

                    let t = context.date.timeIntervalSinceReferenceDate
                    let activeStreams = streams.prefix(columns)
                    let rowsAround = min(rows, 28)

                    for (col, stream) in activeStreams.enumerated() {
                        let x = CGFloat(col) * columnWidth + columnWidth * 0.5
                        let depthSpeed = 0.4 + stream.depth * 1.1
                        let yHead = CGFloat(
                            (t * depthSpeed * 12 + stream.seed)
                                .truncatingRemainder(dividingBy: Double(rows))
                        ) * rowHeight
                        let green = stream.depth
                        let dx = (green - 0.5) * 0.6
                        let glyphCount = Double(glyphs.count)

                        for r in 0..<rowsAround {
                            let y = yHead - CGFloat(r) * rowHeight
                            if y < -rowHeight || y > size.height + rowHeight { continue }
                            let k = stream.seed.advanced(by: Double(r))
                                .truncatingRemainder(dividingBy: glyphCount)
                            let ch = glyphs[Int(k)]
                            let fade = 1.0 - Double(r) / Double(rowsAround)
                            let brightness = 0.18 + 0.82 * (1.0 - fade) * (0.4 + 0.6 * green)
                            let alpha = max(0.0, fade * (0.35 + 0.65 * green))
                            let color = Color(
                                red: 0.0,
                                green: brightness,
                                blue: 0.05 + 0.18 * green
                            )
                            drawGlyph(
                                gc,
                                text: String(ch),
                                x: x + dx,
                                y: y,
                                color: color,
                                alpha: alpha * opacity,
                                size: rowHeight * (0.85 + 0.30 * green)
                            )
                            if r == 0 {
                                drawGlyph(
                                    gc,
                                    text: String(ch),
                                    x: x + dx,
                                    y: y,
                                    color: Color(red: 0.7, green: 1.0, blue: 0.85),
                                    alpha: opacity,
                                    size: rowHeight * (0.95 + 0.20 * green)
                                )
                            }
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .onAppear { ensureStreams(columns: 80) }
    }

    /// Per-column state: how far away (depth) and where it starts (seed).
    fileprivate struct Stream {
        let depth: Double
        let seed: Double
    }

    /// Seed once per column index. Re-runs only when the requested column
    /// count changes (e.g. window resized past the previous capacity).
    private func ensureStreams(columns: Int) {
        if !streams.isEmpty && streams.count == columns { return }
        var rng = SplitMix64(seed: 0x5A17CCED)
        var fresh: [Stream] = []
        fresh.reserveCapacity(columns)
        for _ in 0..<columns {
            let depth = rng.nextDouble()
            let seed  = rng.nextDouble() * 1000
            fresh.append(Stream(depth: depth, seed: seed))
        }
        streams = fresh
    }

    private func drawGlyph(
        _ gc: GraphicsContext,
        text: String,
        x: CGFloat,
        y: CGFloat,
        color: Color,
        alpha: Double,
        size: CGFloat
    ) {
        var local = gc
        local.opacity = alpha
        let resolved = local.resolve(
            Text(verbatim: text)
                .font(.system(size: size, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
        )
        local.draw(resolved, at: CGPoint(x: x, y: y), anchor: .center)
    }
}

// MARK: - Deterministic PRNG

/// Tiny splitmix64 PRNG. Deterministic, fast, no Foundation overhead.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
    mutating func nextDouble() -> Double {
        let n = nextUInt64() >> 11
        return Double(n) / Double(1 << 53)
    }
}
