import Foundation
import AppKit
import CoreGraphics
import SwiftData
import Combine

// MARK: - Public Types

public struct CaptureContext: Sendable {
    public let capture: CapturedImage
    public let cgImage: CGImage
    public let weirdness: Double
    public let vocab: [String]
    public let uiLanguage: String
    public let telemetryEnabled: Bool
    public let pasteAsPlainText: Bool
    public let wordWrapCaptured: Bool
    public let flattenText: Bool
    public let windowCaptureAsTable: Bool
    public let piiRedactionEnabled: Bool
    public let knowledgeModeEnabled: Bool
    public let sourceCodeMode: Bool
    public let translateAfterCapture: Bool
    public let translationTargetLanguage: String
    public let historyLimit: Int

    public init(
        capture: CapturedImage,
        cgImage: CGImage,
        weirdness: Double,
        vocab: [String],
        uiLanguage: String,
        telemetryEnabled: Bool,
        pasteAsPlainText: Bool,
        wordWrapCaptured: Bool,
        flattenText: Bool,
        windowCaptureAsTable: Bool,
        piiRedactionEnabled: Bool,
        knowledgeModeEnabled: Bool,
        sourceCodeMode: Bool,
        translateAfterCapture: Bool,
        translationTargetLanguage: String,
        historyLimit: Int
    ) {
        self.capture = capture
        self.cgImage = cgImage
        self.weirdness = weirdness
        self.vocab = vocab
        self.uiLanguage = uiLanguage
        self.telemetryEnabled = telemetryEnabled
        self.pasteAsPlainText = pasteAsPlainText
        self.wordWrapCaptured = wordWrapCaptured
        self.flattenText = flattenText
        self.windowCaptureAsTable = windowCaptureAsTable
        self.piiRedactionEnabled = piiRedactionEnabled
        self.knowledgeModeEnabled = knowledgeModeEnabled
        self.sourceCodeMode = sourceCodeMode
        self.translateAfterCapture = translateAfterCapture
        self.translationTargetLanguage = translationTargetLanguage
        self.historyLimit = historyLimit
    }
}

public enum CaptureOutcome: Sendable {
    case success(text: String, analysis: AIInferenceService.Analysis?)
    case failure(reason: String, recoveryImageURL: URL?)
}

public protocol CaptureOrchestrator: AnyObject {
    var currentPhase: PipelinePhase { get }
    var isRunning: Bool { get }

    @MainActor
    func execute(context: CaptureContext) async -> CaptureOutcome
}

// MARK: - Implementation

public final class DefaultCaptureOrchestrator: CaptureOrchestrator {

    private let screenshotService: ScreenshotService
    private let ocrService: OCRService
    private let aiService: AIInferenceService
    private let clipboardService: ClipboardService
    private let captureStore: CaptureStore
    private let historyStore: HistoryStore
    private let metadataExtractor: MetadataExtractor
    private let sensitiveDataDetector: SensitiveDataDetector.Type

    @Published public private(set) var currentPhase: PipelinePhase = .idle
    @Published public private(set) var isRunning: Bool = false

    private var cancellables = Set<AnyCancellable>()

    public init(
        screenshotService: ScreenshotService = .shared,
        ocrService: OCRService = .shared,
        aiService: AIInferenceService = .shared,
        clipboardService: ClipboardService = .shared,
        captureStore: CaptureStore = .shared,
        historyStore: HistoryStore = .shared,
        metadataExtractor: MetadataExtractor = .shared,
        sensitiveDataDetector: SensitiveDataDetector.Type = SensitiveDataDetector.self
    ) {
        self.screenshotService = screenshotService
        self.ocrService = ocrService
        self.aiService = aiService
        self.clipboardService = clipboardService
        self.captureStore = captureStore
        self.historyStore = historyStore
        self.metadataExtractor = metadataExtractor
        self.sensitiveDataDetector = sensitiveDataDetector
    }

    @MainActor
    public func execute(context: CaptureContext) async -> CaptureOutcome {
        guard !isRunning else {
            return .failure(reason: "A capture is already in progress", recoveryImageURL: nil)
        }

        isRunning = true
        currentPhase = .ocr

        do {
            // MARK: - OCR
            let langs = context.uiLanguage.isEmpty ? OCRService.automaticLanguages() : [context.uiLanguage]
            let ocrResult = await ocrService.recognizeText(
                in: context.cgImage,
                weirdness: context.weirdness,
                customVocabulary: context.vocab,
                preferredLanguages: langs
            )

            // MARK: - Metadata + PII
            let metadata = metadataExtractor.extract(from: ocrResult.joinedText)
            let report = sensitiveDataDetector.scan(ocrResult.joinedText)
            let redacted = context.piiRedactionEnabled && !report.isClean
            let redactionCount = report.byKind.count
            let scrubbedText = sensitiveDataDetector.scrub(ocrResult.joinedText, report: report)

            // MARK: - Success verdict
            let englishVerdict = EnglishSuccessDetector.judge(
                ocrResult,
                preferredLanguage: context.uiLanguage
            )

            guard englishVerdict.success else {
                currentPhase = .failed(englishVerdict.reason ?? "No English text detected")
                isRunning = false

                if let recoveryURL = try? CacheService.shared.saveRecoveryImage(context.capture) {
                    return .failure(
                        reason: englishVerdict.reason ?? "OCR extraction failed",
                        recoveryImageURL: recoveryURL
                    )
                }
                return .failure(reason: englishVerdict.reason ?? "OCR extraction failed", recoveryImageURL: nil)
            }

            let rawText = ocrResult.joinedText
            let finalText = redacted ? (scrubbedText.isEmpty ? "[REDACTED:ALL]" : scrubbedText) : rawText

            // MARK: - AI Analysis
            currentPhase = .ai
            let analysis = await aiService.analyze(finalText, weirdness: context.weirdness)

            // MARK: - Formatting
            let isWindow = context.capture.mode == .window
            let tableMarkdown = (isWindow && context.windowCaptureAsTable)
                ? TableFormatter.toMarkdownTable(observations: ocrResult.rawObservations)
                : nil

            var outputText: String = context.wordWrapCaptured
                ? Self.flattenWordWrap(tableMarkdown ?? analysis.cleanedText, columns: 80)
                : tableMarkdown ?? analysis.cleanedText

            if context.flattenText {
                outputText = outputText
                    .replacingOccurrences(of: "\r\n", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                outputText = outputText
                    .split(separator: " ")
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }

            // MARK: - Clipboard
            currentPhase = .clipboard
            let attributed: NSAttributedString? = {
                if context.pasteAsPlainText { return nil }
                if let tableMarkdown {
                    let p = NSMutableParagraphStyle()
                    p.lineSpacing = 2.5
                    return NSAttributedString(
                        string: tableMarkdown,
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                            .paragraphStyle: p,
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                }
                return TextFormatter.attributed(
                    from: outputText,
                    analysis: analysis,
                    weirdness: context.weirdness
                )
            }()

            let copyOk = clipboardService.copy(
                outputText,
                attributed: attributed,
                plainTextOnly: context.pasteAsPlainText
            )
            SoundManager.playCaptureComplete()

            // MARK: - Post-capture translation (Snip-to-translate)
            let translatedText: String?
            if context.translateAfterCapture, !context.translationTargetLanguage.isEmpty,
               let translated = await TranslationService.shared.translate(
                outputText,
                to: context.translationTargetLanguage
            ) {
                translatedText = translated
            } else {
                translatedText = nil
            }

            let deliverableText = translatedText ?? outputText

            // MARK: - Persistence
            currentPhase = .completed
            persistCapture(
                outputText: deliverableText,
                ocrResult: ocrResult,
                analysis: analysis,
                capture: context.capture,
                cgImage: context.cgImage,
                piiRedacted: redacted,
                piiCount: redactionCount,
                historyLimit: context.historyLimit
            )

            isRunning = false
            return .success(text: deliverableText, analysis: analysis)

        } catch {
            let reason = error.localizedDescription
            currentPhase = .failed(reason)
            isRunning = false
            return .failure(reason: reason, recoveryImageURL: nil)
        }
    }

    // MARK: - Private

    @MainActor
    private func persistCapture(
        outputText: String,
        ocrResult: OCRResult,
        analysis: AIInferenceService.Analysis,
        capture: CapturedImage,
        cgImage: CGImage,
        piiRedacted: Bool,
        piiCount: Int,
        historyLimit: Int
    ) {
        let aiEntities: [String] = analysis.entities.compactMap { entity in
            switch entity {
            case .url(let s): return s
            case .email(let s): return s
            case .phone(let s): return s
            case .hashtag(let s): return s
            case .mention(let s): return s
            }
        }

        let metadata = metadataExtractor.extract(from: ocrResult.joinedText)
        let metaEntities = metadata.values(for: .url)
            + metadata.values(for: .email)
            + metadata.values(for: .phone)
            + metadata.values(for: .cryptoAddress)
            + metadata.values(for: .trackingNumber)
            + metadata.values(for: .apiKey)
            + metadata.values(for: .creditCard)
            + metadata.values(for: .ipAddress)
            + metadata.values(for: .macAddress)
            + metadata.values(for: .uuid)
            + metadata.values(for: .filePath)
            + metadata.values(for: .sshKey)
            + metadata.values(for: .dockerId)

        let allEntities = Array(Set(aiEntities + metaEntities))

        let record = CaptureRecord(
            mode: capture.mode.rawValue,
            origin: capture.origin.rawValue,
            rect: capture.rect,
            filePath: capture.fileURL.path,
            ocrText: ocrResult.joinedText,
            language: capture.mode == .window ? "Window" : "auto",
            confidence: Double(ocrResult.averageConfidence),
            tags: analysis.keywords,
            notes: "",
            summary: analysis.keywords.prefix(5).joined(separator: ", "),
            entities: allEntities,
            fileSize: (try? FileManager.default.attributesOfItem(atPath: capture.fileURL.path)[.size] as? Int64) ?? 0,
            imageWidth: cgImage.width,
            imageHeight: cgImage.height,
            isFavorite: false,
            applicationName: capture.mode == .window ? "Window" : nil,
            windowTitle: nil
        )
        try? captureStore.save(record)

        historyStore.record(
            capture: capture,
            text: outputText,
            mode: capture.mode,
            limit: historyLimit
        )
    }

    // MARK: - Word-wrap helper

    private static func flattenWordWrap(_ text: String, columns: Int) -> String {
        let maxLen = max(columns, 40)
        return text.enumerateLines { line in
            guard line.count > maxLen else { return line }
            var out = ""
            var currentWord = ""
            for ch in line {
                if ch.isLetterOrDigit || ch.isPunctuation {
                    currentWord.append(ch)
                } else {
                    if currentWord.count > maxLen {
                        var remaining = currentWord
                        while remaining.count > maxLen {
                            let chunk = String(remaining.prefix(maxLen))
                            out.append(chunk)
                            out.append(" ")
                            remaining.removeFirst(maxLen)
                        }
                        out.append(remaining)
                    } else {
                        out.append(currentWord)
                    }
                    out.append(String(ch))
                    currentWord = ""
                }
            }
            if !currentWord.isEmpty {
                if currentWord.count > maxLen {
                    var remaining = currentWord
                    while remaining.count > maxLen {
                        let chunk = String(remaining.prefix(maxLen))
                        out.append(chunk)
                        out.append(" ")
                        remaining.removeFirst(maxLen)
                    }
                    out.append(remaining)
                } else {
                    out.append(currentWord)
                }
            }
            return out
        }
    }
}

// MARK: - Character Classification Helpers

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }

    var isLetter: Bool {
        unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    var isNumber: Bool {
        unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }

    var isPunctuation: Bool {
        unicodeScalars.contains { CharacterSet.punctuationCharacters.contains($0) }
    }
}

extension String {
    fileprivate func enumerateLines(transform: (String) -> String) -> String {
        var result = ""
        var currentLine = ""
        var iterator = makeIterator()

        while let next = iterator.next() {
            if next == "\n" || next == "\r" {
                if next == "\r" {
                    let peek = iterator.next()
                    if peek == "\n" {
                        result.append(transform(currentLine))
                        result.append("\r\n")
                        currentLine = ""
                        continue
                    } else {
                        result.append(transform(currentLine))
                        result.append("\r")
                        if let ch = peek { currentLine = String(ch) } else { currentLine = "" }
                        continue
                    }
                } else {
                    result.append(transform(currentLine))
                    result.append("\n")
                    currentLine = ""
                }
            } else {
                currentLine.append(next)
            }
        }
        if !currentLine.isEmpty {
            result.append(transform(currentLine))
        }
        return result
    }
}
