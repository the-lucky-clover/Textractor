import AppKit

/// Writes extracted text to the pasteboard, optionally with rich-text
/// formatting.
@MainActor
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
}
