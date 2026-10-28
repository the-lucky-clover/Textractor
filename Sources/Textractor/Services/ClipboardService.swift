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

        // Sanitize text to ensure valid UTF-8 for clipboard
        let sanitizedText = sanitizeForClipboard(text)

        let success = pb.setString(sanitizedText, forType: .string)
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
                // Use UTF-8 RTF variant for better Unicode support
                let rtfData = try attributed.data(
                    from: range,
                    documentAttributes: [
                        .documentType: NSAttributedString.DocumentType.rtf,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ]
                )
                pb.setData(rtfData, forType: .rtf)
            } catch {
                LoggerService.shared.warning("RTF pasteboard write failed: \(error.localizedDescription)")
            }
        }

        for extraType in extraPasteboardTypes {
            _ = pb.setString(sanitizedText, forType: .init(extraType))
        }

        TelemetryService.shared.record(
            TelemetryEvent(
                kind: .clipboardWrite,
                success: success,
                meta: [
                    "len": "\(sanitizedText.count)",
                    "rich": attributed != nil ? "1" : "0"
                ]
            ),
            telemetryEnabled: TelemetryService.shared.isEnabled
        )
        return success
    }

    /// Sanitize text for clipboard to ensure valid UTF-8 and remove problematic characters
    private func sanitizeForClipboard(_ text: String) -> String {
        // Ensure valid UTF-8 by converting to data and back
        guard let data = text.data(using: .utf8),
              let sanitized = String(data: data, encoding: .utf8) else {
            // Fallback: replace invalid sequences
            return String(text.unicodeScalars
                .filter { $0.isASCII || $0.value >= 0x20 || $0 == "\n" || $0 == "\t" }
                .map { String($0) }
                .joined())
        }
        return sanitized
    }
}
