import CoreGraphics

/// Conservative fallback for upright vertical glyphs on a nearly uniform background.
/// Reflows original pixels, never synthesizes characters. Complex backgrounds fall back to Vision.
enum VerticalTextReflow {
    struct Column { let image: CGImage; let box: CGRect }
    static func columns(in image: CGImage, glyphWidth: CGFloat) -> [Column] {
        let scale = min(1, 2048 / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * scale)), h = max(1, Int(CGFloat(image.height) * scale))
        let glyph = glyphWidth * CGFloat(image.width) * scale
        guard glyph >= 6, w > 4, h > 4,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let border = (0..<w).flatMap { [Int(pixels[$0]), Int(pixels[(h - 1) * w + $0])] }
            + (0..<h).flatMap { [Int(pixels[$0 * w]), Int(pixels[$0 * w + w - 1])] }
        let background = border.sorted()[border.count / 2]
        guard border.filter({ abs($0 - background) < 15 }).count * 10 >= border.count * 9 else { return [] }
        func ink(_ x: Int, _ y: Int) -> Bool { abs(Int(pixels[y * w + x]) - background) > 50 }
        let xCounts = (0..<w).map { x in (0..<h).reduce(0) { $0 + (ink(x, $1) ? 1 : 0) } }
        let xBands = bands(xCounts, minimum: max(2, h / 500), gap: max(2, Int(glyph * 0.3)))
        var columns: [Column] = []
        for x in xBands.prefix(16) {
            guard CGFloat(x.count) >= glyph * 0.4, CGFloat(x.count) <= glyph * 1.8 else { continue }
            let yCounts = (0..<h).map { y in x.reduce(0) { $0 + (ink($1, y) ? 1 : 0) } }
            let rows = bands(yCounts, minimum: 2, gap: max(1, Int(glyph * 0.12)))
            guard (2...128).contains(rows.count),
                  rows.allSatisfy({ CGFloat($0.count) >= glyph * 0.35 && CGFloat($0.count) <= glyph * 1.6 }),
                  let first = rows.first, let last = rows.last else { continue }
            let cellW = x.count + 12, cellH = (rows.map(\.count).max() ?? 0) + 12
            let outputW = cellW * rows.count
            guard outputW <= 16_000, outputW * cellH <= 4_000_000,
                  let output = CGContext(data: nil, width: outputW, height: cellH, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            output.setFillColor(CGColor(gray: CGFloat(background) / 255, alpha: 1))
            output.fill(CGRect(x: 0, y: 0, width: outputW, height: cellH))
            var complete = true
            for (index, row) in rows.enumerated() {
                let original = CGRect(x: CGFloat(x.lowerBound) / scale, y: CGFloat(row.lowerBound) / scale,
                                      width: CGFloat(x.count) / scale, height: CGFloat(row.count) / scale)
                guard let glyphImage = image.cropping(to: original) else { complete = false; break }
                output.draw(glyphImage, in: CGRect(x: index * cellW + 6, y: (cellH - row.count) / 2,
                                                   width: x.count, height: row.count))
            }
            guard complete, let reflowed = output.makeImage() else { continue }
            columns.append(Column(image: reflowed, box: CGRect(x: CGFloat(x.lowerBound) / CGFloat(w),
                y: 1 - CGFloat(last.upperBound) / CGFloat(h), width: CGFloat(x.count) / CGFloat(w),
                height: CGFloat(last.upperBound - first.lowerBound) / CGFloat(h))))
        }
        return columns
    }
    private static func bands(_ counts: [Int], minimum: Int, gap: Int) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?, last: Int?
        for (index, count) in counts.enumerated() where count >= minimum {
            if let end = last, index - end > gap + 1, let begin = start {
                result.append(begin..<(end + 1)); start = nil
            }
            if start == nil { start = index }
            last = index
        }
        if let start, let last { result.append(start..<(last + 1)) }
        return result
    }
}
