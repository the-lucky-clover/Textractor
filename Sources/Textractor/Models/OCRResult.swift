import Foundation
import CoreGraphics

/// A single piece of recognised text and the bounding rect in image space.
public struct TextObservation: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let text: String
    public let confidence: Float
    /// Normalized rect 0…1 (Vision coordinate space: origin bottom-left)
    public let boundingBox: CGRect

    public init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        boundingBox: CGRect
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Vision's recognition result, with metadata for self-healing logic.
public struct OCRResult: Sendable {
    public let rawObservations: [TextObservation]
    public let recognizedAtSeconds: Double
    public let languageCandidates: [String]
    public let revisionsUsed: [(String, Int)]

    public init(
        rawObservations: [TextObservation],
        recognizedAtSeconds: Double,
        languageCandidates: [String],
        revisionsUsed: [(String, Int)]
    ) {
        self.rawObservations = rawObservations
        self.recognizedAtSeconds = recognizedAtSeconds
        self.languageCandidates = languageCandidates
        self.revisionsUsed = revisionsUsed
    }

    /// Concatenated text reconstructed in reading order.
    ///
    /// Vision returns one observation per text *block/line* with no paragraph
    /// or column awareness, and its `minY` values are noisy, so a naive
    /// `minY` sort joined with newlines both mis-orders and over-splits text.
    /// Instead we cluster observations into lines by vertical proximity
    /// (tolerance derived from the average line height, not a fixed constant),
    /// order lines top-to-bottom, sort each line left-to-right, and join tokens
    /// within a line with spaces and lines with newlines.
    public var joinedText: String {
        guard !rawObservations.isEmpty else { return "" }

        let avgHeight = rawObservations.reduce(CGFloat(0)) { $0 + $1.boundingBox.height }
            / CGFloat(rawObservations.count)
        let lineTolerance = max(avgHeight * 0.5, 0.005)

        // Bucket observations into reading-order lines (top of screen first).
        let byY = rawObservations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
        var lines: [[TextObservation]] = []
        var current: [TextObservation] = []
        var lastMinY: CGFloat?
        for obs in byY {
            if let lastY = lastMinY, abs(obs.boundingBox.minY - lastY) > lineTolerance {
                lines.append(current)
                current = []
            }
            current.append(obs)
            lastMinY = obs.boundingBox.minY
        }
        if !current.isEmpty { lines.append(current) }

        let rendered = lines.map { line in
            line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .map(\.text)
                .joined(separator: " ")
        }.joined(separator: "\n")

        return rendered.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Average confidence across all observations, 0…1.
    public var averageConfidence: Float {
        guard !rawObservations.isEmpty else { return 0 }
        return rawObservations.map(\.confidence).reduce(0, +) / Float(rawObservations.count)
    }

    public var isEmpty: Bool { rawObservations.isEmpty || joinedText.isEmpty }
}
