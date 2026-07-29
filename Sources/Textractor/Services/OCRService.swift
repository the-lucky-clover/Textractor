import Foundation
import Vision
import CoreGraphics
import CoreImage

/// On-device OCR using Apple's Vision framework. Privacy-first — Vision never
/// transmits anything off-device.
public final class OCRService {

    public static let shared = OCRService()

    private init() {}

    // MARK: - Public

    /// Recognize text with self-healing retries driven by the weirdness setting.
    ///
    /// `preferredLanguages` is the user-selected OCR language list from
    /// Settings. An empty list enables **Automatic** detection — Textractor
    /// builds a broad multi-language superset so it can recognise text even
    /// when the captured region is written in a script the macOS system
    /// locale doesn't include. Pass a single-element list to force a specific
    /// language.
    public func recognizeText(
        in cgImage: CGImage,
        weirdness: Double = 0.45,
        customVocabulary: [String] = [],
        preferredLanguages: [String] = []
    ) async -> OCRResult {
        let started = Date()
        let normalized = max(0.0, min(1.0, weirdness))

        var revisionsUsed: [(String, Int)] = []
        var observations: [TextObservation] = []

        // English / Automatic mode uses a single English recogniser
        // ("en-US") so Vision's language correction stays within the English
        // lexicon and never substitutes words from other scripts — that cross-
        // language substitution was the source of "mangled" OCR. The 14-language
        // superset is only used when a non-English language is explicitly chosen.
        let isEnglishMode = preferredLanguages.isEmpty
            || preferredLanguages.first?.lowercased().hasPrefix("en") == true
        let ocrLanguages: [String] = isEnglishMode ? ["en-US"] : preferredLanguages

        // Step 1: accurate, baseline threshold derived from weirdness
        let trial1 = await Task.detached(priority: .userInitiated) { () -> [TextObservation] in
            Self.runSync(
                cgImage: cgImage,
                level: .accurate,
                languages: ocrLanguages,
                minTextHeight: Self.threshold(for: normalized),
                vocab: []
            )
        }.value
        observations = trial1
        revisionsUsed.append(("accurate", 1))

        // Dense English text (code, logs, build commands, tables) is frequently
        // corrupted by language correction swapping identifiers/operators for
        // real words. When the first accurate English pass looks dense, re-run
        // with correction disabled. We only *prefer* that result when it is at
        // least as good (same or more observations, equal-or-higher average
        // confidence) so the new pass can never degrade a perfectly good prose
        // capture into something the success detector rejects.
        if isEnglishMode && !observations.isEmpty && Self.isDenseText(observations) {
            let dense = await Task.detached(priority: .userInitiated) {
                Self.runSync(
                    cgImage: cgImage,
                    level: .accurate,
                    languages: ocrLanguages,
                    minTextHeight: Self.threshold(for: normalized),
                    vocab: [],
                    disableLanguageCorrection: true
                )
            }.value
            let baseConf = observations.reduce(0.0) { $0 + Double($1.confidence) } / Double(max(observations.count, 1))
            let denseConf = dense.isEmpty ? 0.0 : (dense.reduce(0.0) { $0 + Double($1.confidence) } / Double(dense.count))
            if !dense.isEmpty && dense.count >= observations.count && denseConf >= baseConf - 0.02 {
                observations = dense
                revisionsUsed.append(("accurate-no-correction", 1))
                LoggerService.shared.info("[ocr] dense English path: preferred correction-off result (\(dense.count) obs, conf=\(String(format: "%.2f", denseConf)))")
            } else {
                LoggerService.shared.info("[ocr] dense English path: kept correction-on result (\(observations.count) obs, conf=\(String(format: "%.2f", baseConf))) — correction-off was not better")
            }
        }

        // Self-heal Step 1: try .fast when accurate produced nothing.
        if observations.isEmpty {
            TelemetryService.shared.record(
                TelemetryEvent(kind: .ocrRetry, success: false, meta: ["reason": "empty-accurate"]),
                telemetryEnabled: TelemetryService.shared.isEnabled
            )
            observations = await Task.detached(priority: .userInitiated) {
                Self.runSync(
                    cgImage: cgImage,
                    level: .fast,
                    languages: ocrLanguages,
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
                    languages: ocrLanguages,
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
                telemetryEnabled: TelemetryService.shared.isEnabled
            )
            observations = await Task.detached(priority: .userInitiated) {
                Self.runSync(
                    cgImage: cgImage,
                    level: .accurate,
                    languages: ocrLanguages,
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
            telemetryEnabled: TelemetryService.shared.isEnabled
        )

        return result
    }

    // MARK: - Synchronous wrapper

    private static func runSync(
        cgImage: CGImage,
        level: VNRequestTextRecognitionLevel,
        languages: [String]?,
        minTextHeight: CGFloat,
        vocab: [String],
        disableLanguageCorrection: Bool = false
    ) -> [TextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        // Language correction helps prose but mangles dense/code text by
        // substituting identifiers, paths and operators. The dense-text path
        // (English captures only) turns it off.
        request.usesLanguageCorrection = !disableLanguageCorrection
        if let languages, !languages.isEmpty {
            // Vision's .fast level only reliably handles 1-2 languages, so it
            // always gets a single language. .accurate can handle more, but the
            // caller already restricts English/Automatic captures to ["en-US"],
            // so this list is normally just that one code (keeping language
            // correction within the English lexicon). Explicit non-English
            // captures pass their full language list through here unchanged.
            let effective: [String] = (level == .fast) ? Array(languages.prefix(1)) : languages
            request.recognitionLanguages = effective
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

    /// Heuristic: is this an English capture of *dense* text (source code,
    /// build commands, logs, tables) rather than prose? Such text is harmed by
    /// Vision's language correction, which rewrites identifiers, paths and
    /// operators into dictionary words. We treat a result as dense when it has
    /// enough observations and a high ratio of code-like symbols.
    private static func isDenseText(_ observations: [TextObservation]) -> Bool {
        guard observations.count >= Self.denseObservationMinimum else { return false }
        let text = observations.map(\.text).joined(separator: " ")
        guard !text.isEmpty else { return false }
        let symbols = CharacterSet(charactersIn: "/\\.=+{}:;_-()[]<>|%@")
        let symbolCount = text.unicodeScalars.filter { symbols.contains($0) }.count
        return Double(symbolCount) / Double(text.count) > Self.denseSymbolRatio
    }

    private static let denseObservationMinimum = 10
    private static let denseSymbolRatio = 0.06

    private static func threshold(for weirdness: Double) -> CGFloat {
        // 0.0 (strictest) → 0.02, 1.0 (most permissive) → 0.002.
        // Lowered from the previous 0.06 floor so the default pass no longer
        // drops small but legitimate text (e.g. dense UI / code lines on a
        // high-DPI capture). Vision still discards sub-pixel noise below ~0.2%.
        let clamped = max(0.0, min(1.0, weirdness))
        let interval = 0.02 - 0.002
        return 0.002 + (1.0 - clamped) * interval
    }

    /// Curated list of Vision-supported BCP-47 codes used when the user
    /// leaves OCR language on "Automatic". Order matters — Vision picks the
    /// first match, so English (the most common Textractor capture) leads.
    public static let automaticLanguageCatalog: [String] = [
        "en-US", "en-GB",
        "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", "nl-NL",
        "ru-RU", "ja-JP", "ko-KR",
        "zh-Hans", "zh-Hant", "ar-SA"
    ]

    /// Build the "Automatic" language set: the curated catalog + any
    /// `Locale.preferredLanguages` the user has, deduped, preserving order so
    /// the leading English code wins for English-only text.
    static func automaticLanguages() -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for code in automaticLanguageCatalog + Locale.preferredLanguages {
            let key = code.lowercased()
            if seen.insert(key).inserted { ordered.append(code) }
        }
        return ordered
    }
}
