import Foundation
import Vision
import CoreGraphics
import CoreImage

// `CGImage` is internally thread-safe but doesn't conform to `Sendable`. We need
// it across an async/await boundary here, so we declare it @unchecked Sendable.
extension CGImage: @unchecked Sendable {}

/// On-device OCR using Apple's Vision framework. Privacy-first — Vision never
/// transmits anything off-device.
public final class OCRService {

    public static let shared = OCRService()

    private init() {}

    // MARK: - Public

    /// Recognize text with self-healing retries driven by the weirdness setting.
    public func recognizeText(
        in cgImage: CGImage,
        weirdness: Double = 0.45,
        customVocabulary: [String] = []
    ) async -> OCRResult {
        let started = Date()
        let normalized = max(0.0, min(1.0, weirdness))

        var revisionsUsed: [(String, Int)] = []
        var observations: [TextObservation] = []

        // Step 1: accurate, baseline threshold derived from weirdness
        let trial1 = await Task.detached(priority: .userInitiated) { () -> [TextObservation] in
            Self.runSync(
                cgImage: cgImage,
                level: .accurate,
                languages: nil,
                minTextHeight: Self.threshold(for: normalized),
                vocab: []
            )
        }.value
        observations = trial1
        revisionsUsed.append(("accurate", 1))

        // Self-heal Step 1: try .fast when accurate produced nothing.
        if observations.isEmpty {
            TelemetryService.shared.record(
                TelemetryEvent(kind: .ocrRetry, success: false, meta: ["reason": "empty-accurate"]),
                telemetryEnabled: true
            )
            observations = await Task.detached(priority: .userInitiated) {
                Self.runSync(
                    cgImage: cgImage,
                    level: .fast,
                    languages: nil,
                    minTextHeight: 0.0,
                    vocab: []
                )
            }.value
            revisionsUsed.append(("fast", 1))
        }

        // Self-heal Step 2: explicit language hints + custom vocab (only when
        // weirdness is permissive enough).
        if observations.isEmpty && normalized > 0.35 {
            let vocab = normalized > 0.4 ? customVocabulary : []
            observations = await Task.detached(priority: .userInitiated) {
                Self.runSync(
                    cgImage: cgImage,
                    level: .accurate,
                    languages: Self.latinLanguageHints(),
                    minTextHeight: 0.0,
                    vocab: vocab
                )
            }.value
            revisionsUsed.append(("accurate+langs", 1))
        }

        // Self-heal Step 3: dedicated vocab-only run.
        if observations.isEmpty && !customVocabulary.isEmpty {
            TelemetryService.shared.record(
                TelemetryEvent(kind: .ocrRetry, success: false, meta: ["reason": "vocab-fallback"]),
                telemetryEnabled: true
            )
            observations = await Task.detached(priority: .userInitiated) {
                Self.runSync(
                    cgImage: cgImage,
                    level: .accurate,
                    languages: ["en-US"],
                    minTextHeight: 0.0,
                    vocab: customVocabulary
                )
            }.value
            revisionsUsed.append(("accurate+vocab", 1))
        }

        let result = OCRResult(
            rawObservations: observations,
            recognizedAtSeconds: Date().timeIntervalSince(started),
            languageCandidates: [],
            revisionsUsed: revisionsUsed
        )

        TelemetryService.shared.record(
            TelemetryEvent(
                kind: result.isEmpty ? .ocrFailure : .ocrSuccess,
                success: !result.isEmpty,
                latencyMs: result.recognizedAtSeconds * 1000,
                meta: [
                    "candidates": "\(observations.count)",
                    "conf": String(format: "%.2f", result.averageConfidence),
                    "attempts": "\(revisionsUsed.count)"
                ]
            ),
            telemetryEnabled: true
        )

        return result
    }

    // MARK: - Synchronous wrapper

    private static func runSync(
        cgImage: CGImage,
        level: VNRequestTextRecognitionLevel,
        languages: [String]?,
        minTextHeight: CGFloat,
        vocab: [String]
    ) -> [TextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        if let languages, !languages.isEmpty {
            request.recognitionLanguages = languages
        }
        request.minimumTextHeight = Float(minTextHeight)
        if !vocab.isEmpty {
            request.customWords = vocab
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            LoggerService.shared.warning("Vision perform failed: \(error.localizedDescription)")
            return []
        }
        guard let raw = request.results else { return [] }
        return raw.compactMap { obs -> TextObservation? in
            guard let top = obs.topCandidates(1).first else { return nil }
            return TextObservation(
                text: top.string,
                confidence: top.confidence,
                boundingBox: obs.boundingBox
            )
        }
    }

    // MARK: - Tunables

    private static func threshold(for weirdness: Double) -> CGFloat {
        // 0.0 → 0.06 (ignore very small text), 1.0 → 0.005 (capture anything).
        let clamped = max(0.0, min(1.0, weirdness))
        let interval = 0.06 - 0.005
        return 0.005 + (1.0 - clamped) * interval
    }

    private static func latinLanguageHints() -> [String] {
        ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"]
    }
}
