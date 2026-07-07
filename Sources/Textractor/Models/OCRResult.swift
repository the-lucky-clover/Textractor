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

    /// Concatenated text, ordered top-to-bottom-left-to-right by Vision bounding-box.
    public var joinedText: String {
        let sorted = rawObservations.sorted { lhs, rhs in
            // Vision boundingBox.minY is measured from the bottom-left.
            // Higher Y = higher on the screen.
            if abs(lhs.boundingBox.minY - rhs.boundingBox.minY) > 0.01 {
                return lhs.boundingBox.minY > rhs.boundingBox.minY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return sorted.map(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Average confidence across all observations, 0…1.
    public var averageConfidence: Float {
        guard !rawObservations.isEmpty else { return 0 }
        return rawObservations.map(\.confidence).reduce(0, +) / Float(rawObservations.count)
    }

    public var isEmpty: Bool { rawObservations.isEmpty || joinedText.isEmpty }
}
