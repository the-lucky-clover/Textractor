import AppKit
import AVFoundation
import Vision
import CoreGraphics

/// Session-only accumulation: captured text is not persisted in an extra hidden store.
public struct CaptureAccumulator {
    public private(set) var entries: [String] = []
    public static let characterLimit = 1_000_000
    public var text: String { entries.joined(separator: "\n\n") }

    @discardableResult
    public mutating func append(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let separatorCount = entries.isEmpty ? 0 : 2
        guard text.count + separatorCount + value.count <= Self.characterLimit else { return false }
        entries.append(value)
        return true
    }
    public mutating func undo() { if !entries.isEmpty { entries.removeLast() } }
    public mutating func clear() { entries.removeAll() }
}

@MainActor
public final class CaptureExtras: ObservableObject {
    public static let shared = CaptureExtras()
    @Published public private(set) var batch = CaptureAccumulator()
    public private(set) var lastDeliveredText: String?
    public func beginCapture() { lastDeliveredText = nil }
    private let speech = AVSpeechSynthesizer()

    @discardableResult
    public func deliver(_ text: String, attributed: NSAttributedString? = nil,
                        settings: AppSettings) -> Bool {
        var candidate = batch
        if settings.additiveClipboard, !candidate.append(text) { return false }
        let output = settings.additiveClipboard ? candidate.text : text
        let copied = ClipboardService.shared.copy(output,
            attributed: settings.additiveClipboard ? nil : attributed,
            plainTextOnly: settings.pasteAsPlainText || settings.additiveClipboard)
        guard copied else { return false }
        lastDeliveredText = text
        if settings.additiveClipboard { batch = candidate }
        if settings.readAloud { speak(text, settings: settings) }
        return true
    }

    public func clearBatch() { batch.clear() }
    public func undoBatch() {
        var candidate = batch
        candidate.undo()
        if ClipboardService.shared.copy(candidate.text, plainTextOnly: true) { batch = candidate }
    }
    public func speak(_ text: String, settings: AppSettings) {
        speech.stopSpeaking(at: .immediate)
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: settings.uiLanguage.isEmpty ? "en-US" : settings.uiLanguage)
        let rate = Float(min(1, max(0, settings.speechRate)))
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate + rate * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
        speech.speak(utterance)
    }
    public func stopSpeaking() { speech.stopSpeaking(at: .immediate) }
}

public enum BarcodeRecognition {
    /// Return distinct payloads in visual reading order; never open URLs automatically.
    public static func recognize(_ image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        var seen = Set<String>()
        return (request.results ?? []).sorted {
            if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.03 {
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }.compactMap { observation in
            guard let value = observation.payloadStringValue, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}
