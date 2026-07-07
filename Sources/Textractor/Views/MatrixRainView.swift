import SwiftUI

/// Matrix-rain backdrop. Drops random glyphs (kanji + katakana + ASCII) in
/// vertical columns from top to bottom of the host frame. Columns at different
/// depths have different speeds and brightness for the requested 3D effect.
///
/// Animation is driven by a `TimelineView(.animation)` so the view redraws at
/// the system-tick rate (≈30 fps) without forcing an explicit Timer. The
/// underlying character stream is fully deterministic per column index so the
/// animation looks steady even when re-laid-out.
struct MatrixRainView: View {

    /// 0.0 → invisible, 1.0 → fully on. Driving this from outside gives the
    /// caller an animated fade-in / fade-out.
    var opacity: Double

    private let glyphs: [Character] =
        "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ".prefix(40)
        + Array("日月火水木金土山川田人口")
        + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        + Array("0123456789")

    private let columnWidth: CGFloat = 16
    private let rowHeight: CGFloat = 18

    /// A state model that holds per-column drops over time. We update inside a
    /// single `body` recomputation; the heavy lifting is one Canvas pass.
    @State private var phase: Double = 0
    @State private var streams: [Stream] = []

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let columns = max(8, Int(size.width / columnWidth))
            let rows = max(8, Int(size.height / rowHeight))
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                Canvas { gc, _ in
                    // Background fill — pure black so the greens pop.
                    gc.fill(Path(CGRect(origin: .zero, size: size)),
                            with: .color(.black))

                    // Phase advances with elapsed time; speed and depth drive
                    // visible vertical position per stream.
                    let t = context.date.timeIntervalSinceReferenceDate
                    ensureStreams(columns: columns)
                    let activeStreams = streams.prefix(columns)

                    for (col, stream) in activeStreams.enumerated() {
                        let x = CGFloat(col) * columnWidth + columnWidth * 0.5
                        let depthSpeed: Double  = 0.4 + stream.depth * 1.1
                        let yHead = CGFloat((t * depthSpeed * 12 + stream.seed)
                                            .truncatingRemainder(dividingBy: Double(rows))) * rowHeight
                        let charsToDraw = min(rows, 28)
                        for r in 0..<charsToDraw {
                            let y = yHead - CGFloat(r) * rowHeight
                            if y < -rowHeight || y > size.height + rowHeight { continue }
                            let k = (stream.seed.advanced(by: r)).truncatingRemainder(dividingBy: Double(glyphs.count))
                            let ch = glyphs[Int(k)]
                            let fade = 1.0 - Double(r) / Double(charsToDraw)
                            let green: Double = stream.depth  // 0 = far, 1 = near
                            let brightness = 0.18 + 0.82 * (1.0 - fade) * (0.4 + 0.6 * green)
                            let alpha = max(0.0, fade * (0.35 + 0.65 * green))
                            // Slight horizontal jitter on depth for parallax.
                            let dx = (green - 0.5) * 0.6
                            drawGlyph(
                                gc,
                                text: String(ch),
                                x: x + dx,
                                y: y,
                                color: Color(red: 0.0, green: brightness, blue: 0.05 + 0.18 * green),
                                alpha: alpha * opacity,
                                size: rowHeight * (0.85 + 0.30 * green)
                            )
                            if r == 0 {
                                // White "head" for the leading drop
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
                .opacity(opacity)
                .onAppear { ensureStreams(columns: columns) }
            }
        }
        .background(Color.black)
    }

    private func ensureStreams(columns: Int) {
        if streams.count == columns { return }
        // Deterministic seeding so reloads don't shuffle.
        var rng = SplitMix64(seed: 0x5A17CCED)
        var fresh: [Stream] = []
        fresh.reserveCapacity(columns)
        for i in 0..<columns {
            let depth = rng.nextDouble()  // 0.0 – 1.0
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
        let resolved = local.resolve(Text(verbatim: text).font(.system(size: size, weight: .heavy, design: .monospaced)).foregroundStyle(color))
        local.draw(resolved, at: CGPoint(x: x, y: y), anchor: .center)
    }

    private struct Stream {
        let depth: Double   // 0 = far, 1 = near
        let seed: Double
    }
}

/// Tiny splitmix64 PRNG — deterministic, fast, no Foundation overhead.
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
        let n = nextUInt64() >> 11                  // 53 bits of mantissa
        return Double(n) / Double(1 << 53)
    }
}
