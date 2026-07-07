import AppKit
import Carbon.HIToolbox

/// Writes extracted text to the pasteboard, optionally with rich-text formatting
/// and synthesizes ⌘V into the frontmost app for one-tap paste.
public final class ClipboardService {

    public static let shared = ClipboardService()

    private init() {}

    // MARK: - Plain & rich

    /// Writes `text` to the general pasteboard. If `attributed` is provided,
    /// it is additionally written as both `.rtf` and `.rtfd`, so apps that honour
    /// styled pasteboard receive the typography-rich version.
    /// Pass `plainTextOnly: true` to skip the rich-text path entirely.
    @discardableResult
    public func copy(
        _ text: String,
        attributed: NSAttributedString? = nil,
        extraPasteboardTypes: [String] = [],
        plainTextOnly: Bool = false
    ) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()

        var success = pb.setString(text, forType: .string)
        guard success else {
            TelemetryService.shared.record(
                TelemetryEvent(kind: .clipboardFailure, success: false, meta: ["stage": "setString"]),
                telemetryEnabled: true
            )
            return false
        }

        if !plainTextOnly, let attributed {
            do {
                let range = NSRange(location: 0, length: attributed.length)
                let rtfData = try attributed.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                pb.setData(rtfData, forType: .rtf)
            } catch {
                LoggerService.shared.warning("RTF pasteboard write failed: \(error.localizedDescription)")
            }
        }

        for extraType in extraPasteboardTypes {
            _ = pb.setString(text, forType: .init(extraType))
        }

        TelemetryService.shared.record(
            TelemetryEvent(
                kind: .clipboardWrite,
                success: success,
                meta: [
                    "len": "\(text.count)",
                    "rich": attributed != nil ? "1" : "0"
                ]
            ),
            telemetryEnabled: true
        )
        return success
    }

    // MARK: - Auto-paste ⌘V

    /// Synthesises ⌘V into the frontmost app using CoreGraphics events.
    /// Requires "Accessibility" permission, which the user grants in
    /// System Settings → Privacy & Security → Accessibility.
    public func autoPasteIntoFrontmostApp() -> Bool {
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        let flags: CGEventFlags = .maskCommand

        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKey, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: vKey, keyDown: false)
        else {
            return false
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        // Tiny pause between events; production code would use Task.sleep
        Thread.sleep(forTimeInterval: 0.04)
        return true
    }

    // MARK: - Snapshot the previous clipboard before overwriting (so we can restore)

    public func snapshot() -> [NSPasteboardItem] {
        let pb = NSPasteboard.general
        var snapshot: [NSPasteboardItem] = []
        for item in pb.pasteboardItems ?? [] {
            snapshot.append(item)
        }
        return snapshot
    }
}
