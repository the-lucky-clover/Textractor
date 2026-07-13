import AppKit
import Carbon.HIToolbox

/// Writes extracted text to the pasteboard, optionally with rich-text
/// formatting. Can also synthesise ⌘V to auto-paste into the frontmost app when
/// the user opts in.
public final class ClipboardService {

    public static let shared = ClipboardService()

    private init() {}

    // MARK: - Plain & rich

    /// Writes `text` to the general pasteboard. If `attributed` is provided,
    /// it is additionally written as `.rtf` so apps that honour styled
    /// pasteboards receive the typography-rich version.
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

        let success = pb.setString(text, forType: .string)
        guard success else {
            TelemetryService.shared.record(
                TelemetryEvent(kind: .clipboardFailure, success: false, meta: ["stage": "setString"]),
                telemetryEnabled: TelemetryService.shared.isEnabled
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
            telemetryEnabled: TelemetryService.shared.isEnabled
        )
        return success
    }

    // MARK: - Snapshot

    /// Snapshot the previous pasteboard (used for restore-on-confirm flows).
    public func snapshot() -> [NSPasteboardItem] {
        let pb = NSPasteboard.general
        return pb.pasteboardItems ?? []
    }

    // MARK: - Auto-paste

    /// Synthesise ⌘V into the frontmost app's key window to paste whatever is on the
    /// general pasteboard. Convenience wrapper around `synthesizePaste()`.
    /// Returns `true` if the keystroke was dispatched, `false` if accessibility is
    /// not granted or the frontmost app can't accept input.
    @discardableResult
    public func autoPasteIntoFrontmostApp() -> Bool {
        guard AXIsProcessTrusted() else {
            LoggerService.shared.warning("Auto-paste skipped — Accessibility permission not granted")
            return false
        }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return false
        }
        synthesizePaste()
        return true
    }

    /// Synthesise a ⌘V keystroke into whatever app is now frontmost, so the
    /// freshly-copied text pastes automatically. Requires Accessibility
    /// permission; silently no-ops if it isn't granted. Posted after a short
    /// delay so the previously-active app has time to regain focus once our
    /// capture overlay / popover has dismissed.
    public func synthesizePaste() {
        guard AXIsProcessTrusted() else {
            LoggerService.shared.warning("Auto-paste skipped — Accessibility permission not granted")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKey = CGKeyCode(kVK_ANSI_V)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
            else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
