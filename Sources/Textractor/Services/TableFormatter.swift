import Foundation
import CoreGraphics

/// `TableFormatter` clusters Vision `TextObservation` items into rows + columns
/// and emits a Markdown table when the alignment is consistent. Otherwise it
/// returns `nil` so the pipeline can fall back to flat text.
public enum TableFormatter {

    public struct Options {
        public var yBucketTolerance: CGFloat = 0.012   // Vision Y tolerance
        public var requireUniformColumns: Bool = true
        public var minRows: Int = 2
        public var minColumns: Int = 2
        public init() {}
    }

    /// Returns a Markdown table if the observations look tabular.
    public static func toMarkdownTable(
        observations: [TextObservation],
        options: Options = Options()
    ) -> String? {
        guard observations.count >= options.minRows * options.minColumns else { return nil }

        // Sort top-to-bottom (Vision Y: higher = upper on screen).
        let sorted = observations.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > options.yBucketTolerance {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        // Cluster by Y-bucket
        var rows: [[TextObservation]] = []
        var currentBucket: [TextObservation] = []
        var currentY: CGFloat? = nil

        for obs in sorted {
            if let y = currentY, abs(obs.boundingBox.midY - y) <= options.yBucketTolerance {
                currentBucket.append(obs)
            } else {
                if !currentBucket.isEmpty { rows.append(currentBucket) }
                currentBucket = [obs]
                currentY = obs.boundingBox.midY
            }
        }
        if !currentBucket.isEmpty { rows.append(currentBucket) }

        guard rows.count >= options.minRows else { return nil }

        // Per-row, sorted by X.
        rows = rows.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }

        // Column consistency check.
        let columnCounts = rows.map(\.count)
        let avgCols = columnCounts.reduce(0, +) / columnCounts.count
        let maxCols = columnCounts.max() ?? 0
        let consistent = options.requireUniformColumns
            ? columnCounts.allSatisfy { abs($0 - avgCols) <= 1 }
            : true
        guard maxCols >= options.minColumns, consistent else { return nil }

        // Determine markdown column widths.
        var lines: [String] = []

        for (i, row) in rows.enumerated() {
            let cells: [String] = row.map { $0.text.trimmingCharacters(in: .whitespaces) }
            // Pad missing cells with empty strings.
            var padded = cells
            while padded.count < maxCols { padded.append("") }
            lines.append("| " + padded.joined(separator: " | ") + " |")

            if i == 0 {
                lines.append("| " + Array(repeating: "---", count: maxCols).joined(separator: " | ") + " |")
            }
        }

        return lines.joined(separator: "\n")
    }
}
