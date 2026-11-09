import AppKit
import AVFoundation
import Vision
import CoreGraphics
import Carbon.HIToolbox
import ApplicationServices

/// Bounded capture accumulation. Persistence is an explicit Settings option.
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
    private let pasteboard: NSPasteboard
    private let copyText: (String, NSAttributedString?, Bool) -> Bool
    private let persistence: AdditiveClipboardPersistence
    private var persistent = false
    private var undoSnapshot: CaptureAccumulator?
    @Published public private(set) var canUndo = false
    @Published public private(set) var persistenceError: String?
    private var ownedClipboardChange: Int?
    private var globalPasteMonitor: Any?
    private var localPasteMonitor: Any?
    private var clearOnPaste = false

    init(persistence: AdditiveClipboardPersistence = .init(url: AdditiveClipboardPersistence.defaultURL),
         pasteboard: NSPasteboard = .general,
         copyText: ((String, NSAttributedString?, Bool) -> Bool)? = nil) {
        self.persistence = persistence
        self.pasteboard = pasteboard
        self.copyText = copyText ?? { text, attributed, plain in
            ClipboardService.shared.copy(text, attributed: attributed, plainTextOnly: plain)
        }
    }

    public func configure(settings: AppSettings) {
        if settings.persistAdditiveClipboard != persistent || persistenceError != nil {
            do {
                if settings.persistAdditiveClipboard {
                    if batch.entries.isEmpty { batch = try persistence.load() }
                    else { try persistence.save(batch) }
                } else { try persistence.remove() }
                persistent = settings.persistAdditiveClipboard
                persistenceError = nil
            } catch { persistenceError = "Additive history could not be read or saved. Original file retained: \(error.localizedDescription)" }
        }
        clearOnPaste = settings.clearAdditiveOnPaste && DistributionPolicy.supportsGlobalPasteObservation
        #if !APP_STORE
        if clearOnPaste, globalPasteMonitor == nil {
            globalPasteMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in self?.observePaste(event) }
            }
            localPasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.observePaste(event)
                return event
            }
        } else if !clearOnPaste {
            if let globalPasteMonitor { NSEvent.removeMonitor(globalPasteMonitor) }
            if let localPasteMonitor { NSEvent.removeMonitor(localPasteMonitor) }
            globalPasteMonitor = nil; localPasteMonitor = nil
        }
        #endif
    }

    public static func isOwnedPaste(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                                    clipboardChange: Int, ownedChange: Int?, clipboardText: String?, batchText: String) -> Bool {
        keyCode == UInt16(kVK_ANSI_V) && modifiers.intersection([.command, .option, .control]) == .command
            && ownedChange == clipboardChange && !batchText.isEmpty && clipboardText == batchText
    }
    private func observePaste(_ event: NSEvent) {
        guard clearOnPaste, Self.isOwnedPaste(keyCode: event.keyCode, modifiers: event.modifierFlags,
            clipboardChange: pasteboard.changeCount, ownedChange: ownedClipboardChange,
            clipboardText: pasteboard.string(forType: .string), batchText: batch.text) else { return }
        clearBatch() // Only history changes. The destination still receives the unchanged pasteboard.
    }
    @discardableResult
    private func commit(_ candidate: CaptureAccumulator, rememberUndo: Bool = true) -> Bool {
        do {
            guard persistenceError == nil else { return false }
            if persistent { try persistence.save(candidate) }
            if rememberUndo { undoSnapshot = batch; canUndo = true }
            batch = candidate
            return true
        } catch { persistenceError = "Additive history could not be saved: \(error.localizedDescription)"; return false }
    }
    public func retryPersistence(settings: AppSettings) {
        persistenceError = nil
        if persistent { do { try persistence.save(batch) } catch { persistenceError = error.localizedDescription } }
        else { configure(settings: settings) }
    }
    public func discardAllHistory() {
        do {
            try persistence.remove()
            batch.clear(); undoSnapshot = nil; canUndo = false; ownedClipboardChange = nil; persistenceError = nil
        } catch { persistenceError = error.localizedDescription }
    }

    @discardableResult
    public func deliver(_ text: String, attributed: NSAttributedString? = nil,
                        settings: AppSettings) -> Bool {
        lastDeliveredText = nil
        var candidate = batch
        if settings.additiveClipboard, !candidate.append(text) { return false }
        let output = settings.additiveClipboard ? candidate.text : text
        let copied = copyText(output, settings.additiveClipboard ? nil : attributed,
                              settings.pasteAsPlainText || settings.additiveClipboard)
        guard copied else { return false }
        if settings.additiveClipboard {
            guard commit(candidate) else { return false }
            ownedClipboardChange = pasteboard.changeCount
        } else { ownedClipboardChange = nil }
        if settings.automaticallyOpenLinks { CapturedLinkPolicy.links(in: text).forEach { _ = NSWorkspace.shared.open($0) } }
        lastDeliveredText = text
        if settings.readAloud { speak(text, settings: settings) }
        return true
    }

    public func clearBatch() {
        guard !batch.entries.isEmpty else { return }
        if commit(CaptureAccumulator()) { ownedClipboardChange = nil }
    }
    public func undoBatch() {
        guard let previous = undoSnapshot else { return }
        let ownsClipboard = ownedClipboardChange == pasteboard.changeCount
            && pasteboard.string(forType: .string) == batch.text
        if commit(previous, rememberUndo: false) {
            undoSnapshot = nil; canUndo = false
            if ownsClipboard, copyText(previous.text, nil, true) {
                ownedClipboardChange = pasteboard.changeCount
            }
        }
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
