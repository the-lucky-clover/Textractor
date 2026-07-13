import AppKit
import Foundation

/// `ShareService` exposes share actions for Mail, Messages/SMS, and AirDrop
/// via NSSharingService.
public final class ShareService {

    public static let shared = ShareService()

    private init() {}

    // MARK: - Public constants

    public enum Provider {
        case email, message, airDrop
    }

    // MARK: - High-level entry point

    @MainActor
    public func share(
        text: String,
        caption: String = "",
        via provider: Provider,
        attachmentURL: URL? = nil
    ) {
        var items: [Any] = []
        if !caption.isEmpty { items.append(caption + "\n\n" + text) }
        else                 { items.append(text) }
        if let attachmentURL { items.append(attachmentURL) }

        switch provider {
        case .email:
            performEmail(items: items)
            record(.shareEmail, success: true)

        case .message:
            performMessage(items: items)
            record(.shareMessage, success: true)

        case .airDrop:
            performAirDrop(items: items)
            record(.shareAirDrop, success: true)
        }
    }

    // MARK: - Per-provider actions

    @MainActor
    private func performEmail(items: [Any]) {
        if let s = NSSharingService(named: .composeEmail), s.canPerform(withItems: items) {
            s.perform(withItems: items)
            return
        }
        // Fallback: mailto URL
        let subject = "Text from Textractor"
        let body = (items.first as? String) ?? ""
        let urlStr = "mailto:?subject=\(subject.urlEncoded)&body=\(body.urlEncoded)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func performMessage(items: [Any]) {
        if let s = NSSharingService(named: .composeMessage), s.canPerform(withItems: items) {
            s.perform(withItems: items)
            return
        }
        // Fallback: imessage:// URL with body parameter (likely won't carry attachments).
        if let body = items.first as? String, let url = URL(string: "imessage:&body=\(body.urlEncoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func performAirDrop(items: [Any]) {
        if let s = NSSharingService(named: .sendViaAirDrop), s.canPerform(withItems: items) {
            s.perform(withItems: items)
        }
    }

    // MARK: - Sharing picker (full freedom)

    @MainActor
    public func showPicker(items: [Any], from rect: NSRect = .zero) {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: rect, of: NSApp.mainWindow?.contentView ?? NSView(), preferredEdge: .minY)
    }

    // MARK: - Telemetry

    private func record(_ kind: TelemetryEvent.Kind, success: Bool) {
        TelemetryService.shared.record(
            TelemetryEvent(kind: kind, success: success),
            telemetryEnabled: TelemetryService.shared.isEnabled
        )
    }
}

extension String {
    var urlEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
