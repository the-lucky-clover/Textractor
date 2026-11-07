import AppKit
import PDFKit

/// AppKit's Continuity Camera service returns a private pasteboard to this responder.
/// No file picker is presented as a substitute for the device camera.
@MainActor
final class ContinuityCameraController: NSObject, NSWindowDelegate {
    static let shared = ContinuityCameraController()
    private var panel: NSPanel?
    private var pending: CheckedContinuation<[URL], Error>?

    func capture() async throws -> [URL] {
        guard pending == nil else { throw ScreenshotError.processingFailed("Camera import is already open.") }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            let view = CameraImportView(frame: NSRect(x: 0, y: 0, width: 440, height: 260))
            view.onImport = { [weak self] result in self?.finish(result) }
            let window = NSPanel(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Import from iPhone or iPad"
            window.contentView = view
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .floating
            panel = window
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }
    }

    func windowWillClose(_ notification: Notification) { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<[URL], Error>) {
        guard let continuation = pending else { return }
        pending = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
        continuation.resume(with: result)
    }
}

@MainActor
private final class CameraImportView: NSView, NSServicesMenuRequestor {
    var onImport: ((Result<[URL], Error>) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: "Take a photo or scan a document")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "Click Choose device, then select your iPhone or iPad. Use the same Apple Account with two-factor authentication, Wi-Fi and Bluetooth enabled, and keep devices nearby. If no device appears, close this window and import a saved image instead.")
        let button = NSButton(title: "Choose device…", target: self, action: #selector(chooseDevice))
        button.setAccessibilityIdentifier("continuity.chooseDevice")
        let stack = NSStackView(views: [title, help, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24)
        ])
    }
    required init?(coder: NSCoder) { nil }

    @objc private func chooseDevice() {
        window?.makeFirstResponder(self)
        guard let event = NSApp.currentEvent else { return }
        // AppKit inserts the device submenu for an image-capable requestor.
        NSMenu.popUpContextMenu(NSMenu(title: "Import from device"), with: event, for: self)
    }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        NSMenu.popUpContextMenu(NSMenu(title: "Import from device"), with: event, for: self)
    }
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if let type = returnType, NSImage.imageTypes.contains(type.rawValue) || type == .pdf { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }
    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        do {
            let files = try CameraImportDecoder.decode(pasteboard)
            onImport?(.success(files))
            return true
        } catch {
            onImport?(.failure(error))
            return false
        }
    }
}

@MainActor
enum CameraImportDecoder {
    static let maximumPages = 50
    static func decode(_ pasteboard: NSPasteboard) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TextractorCamera-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var urls: [URL] = []
        func write(_ image: NSImage) throws {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { throw ScreenshotError.encodingFailed }
            let url = directory.appendingPathComponent("page-\(urls.count + 1).png")
            try png.write(to: url, options: .atomic)
            urls.append(url)
        }
        do {
            if let data = pasteboard.data(forType: .pdf), let document = PDFDocument(data: data) {
                guard (1...maximumPages).contains(document.pageCount) else {
                    throw ScreenshotError.processingFailed("Import 1–50 scanned pages at a time.")
                }
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { throw ScreenshotError.encodingFailed }
                    let bounds = page.bounds(for: .mediaBox)
                    guard bounds.width > 0, bounds.height > 0 else { throw ScreenshotError.encodingFailed }
                    let scale = min(2.5, 2400 / max(bounds.width, bounds.height))
                    try write(page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox))
                }
            } else if let image = NSImage(pasteboard: pasteboard) {
                try write(image)
            } else { throw ScreenshotError.processingFailed("The device returned an unsupported image or document.") }
            return urls
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
