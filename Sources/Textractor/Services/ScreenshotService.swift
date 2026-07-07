import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Errors thrown by `ScreenshotService`.
public enum ScreenshotError: LocalizedError {
    case permissionDenied
    case noDisplay
    case noWindow
    case imageCreationFailed
    case fileLoadFailed(URL)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:    return "Screen Recording permission is required. Grant it in System Settings → Privacy & Security → Screen Recording, then re-launch Textractor."
        case .noDisplay:           return "No displays were detected."
        case .noWindow:            return "The selected window is not visible."
        case .imageCreationFailed: return "CoreGraphics could not build a screenshot."
        case .fileLoadFailed(let url):  return "Image could not be loaded from \(url.path)."
        case .encodingFailed:      return "Failed to encode image data."
        }
    }
}

/// `WindowDescriptor` describes a visible window discovered by `enumerateWindows`.
public struct WindowDescriptor: Identifiable, Hashable, Sendable {
    public let id: CGWindowID
    public let name: String?
    public let ownerName: String?
    public let bounds: CGRect
    public let layer: Int
    public let alpha: Double
    public let isOnScreen: Bool

    public init(
        id: CGWindowID,
        name: String?,
        ownerName: String?,
        bounds: CGRect,
        layer: Int,
        alpha: Double,
        isOnScreen: Bool
    ) {
        self.id = id
        self.name = name
        self.ownerName = ownerName
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
        self.isOnScreen = isOnScreen
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let ownerName, !ownerName.isEmpty { return ownerName }
        return "Window \(id)"
    }

    /// Filter out SystemUI chrome, dock, etc.
    public var isCaptureEligible: Bool {
        return layer == 0 && isOnScreen && bounds.width > 32 && bounds.height > 32
    }
}

/// Captures regions, windows, full screens, and arbitrary image files.
/// Writes PNGs to `NSTemporaryDirectory`/Textractor/<uuid>.png and returns
/// `CapturedImage` for downstream consumers.
public final class ScreenshotService {

    public static let shared = ScreenshotService()

    private init() {}

    // MARK: - Public API

    /// Capture a rectangular region from a particular screen (point in global coords).
    public func captureRegion(_ rect: CGRect) async throws -> CapturedImage {
        LoggerService.shared.info("Capturing region \(NSStringFromRect(rect))")
        TelemetryService.shared.record(
            TelemetryEvent(kind: .captureRegion, success: true, meta: [
                "w": "\(Int(rect.width))", "h": "\(Int(rect.height))"
            ]),
            telemetryEnabled: true
        )

        let imageOptions: CGWindowImageOption = [.bestResolution]
        guard let img = CGWindowListCreateImage(
            rect,
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID,
            imageOptions
        ) else {
            throw ScreenshotError.imageCreationFailed
        }
        return try writeToDisk(img, mode: .crosshair, origin: .region, rect: rect, screenIndex: 0)
    }

    /// Capture a single window by id (CGWindowListCreateImage with optionIncludingWindow).
    public func captureWindow(_ windowID: CGWindowID) async throws -> (CapturedImage, WindowDescriptor) {
        guard let window = enumerateWindows().first(where: { $0.id == windowID }) else {
            throw ScreenshotError.noWindow
        }
        LoggerService.shared.info("Capturing window \(windowID) '\(window.displayName)'")
        TelemetryService.shared.record(
            TelemetryEvent(kind: .captureWindow, success: true, meta: [
                "id": "\(windowID)",
                "name": window.displayName
            ]),
            telemetryEnabled: true
        )

        let imageOptions: CGWindowImageOption = [.bestResolution]
        guard let img = CGWindowListCreateImage(
            CGRect.null,
            [.optionIncludingWindow],
            CGWindowID(windowID),
            imageOptions
        ) else {
            throw ScreenshotError.imageCreationFailed
        }
        let captured = try writeToDisk(img, mode: .window, origin: .window, rect: window.bounds, screenIndex: 0)
        return (captured, window)
    }

    /// Capture all displays. Returns one `CapturedImage` per display, top-to-bottom.
    public func captureFullScreen() async throws -> [CapturedImage] {
        let displays = NSScreen.screens
        guard !displays.isEmpty else { throw ScreenshotError.noDisplay }

        LoggerService.shared.info("Capturing full screen (\(displays.count) displays)")
        TelemetryService.shared.record(
            TelemetryEvent(kind: .captureRegion, success: true, meta: ["mode": "fullscreen"]),
            telemetryEnabled: true
        )

        var results: [CapturedImage] = []
        // Use CGWindowListCreateImage with all windows/desktop excluded - this captures
        // pixels of the *whole display surface* including non-window UI (dock, menu).
        // We restrict to a rect that covers the primary display, then iterate.
        let primaryFrame = displays.first?.frame ?? .zero
        let primaryDisplayID = displays.first.flatMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
        } ?? 0

        let composedBounds = displays.reduce(into: CGRect.null) { acc, screen in
            acc = acc.union(screen.frame)
        }

        if let comp = CGWindowListCreateImage(
            composedBounds,
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID,
            [.bestResolution]
        ) {
            // Single composed capture across all displays.
            let img = try writeToDisk(
                comp,
                mode: .crosshair,
                origin: .fullscreen,
                rect: composedBounds,
                screenIndex: 0
            )
            results.append(img)
        } else if let img = CGDisplayCreateImage(primaryDisplayID) {
            let captured = try writeToDisk(
                img,
                mode: .crosshair,
                origin: .fullscreen,
                rect: primaryFrame,
                screenIndex: 0
            )
            results.append(captured)
        } else {
            throw ScreenshotError.imageCreationFailed
        }

        return results
    }

    /// Load an arbitrary image file (PNG/JPG/HEIC) — used by drag-and-drop,
    /// "Open File…", and Continuity-Camera driven workflows.
    public func captureFromFile(at url: URL) async throws -> CapturedImage {
        LoggerService.shared.info("Loading image file: \(url.path)")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ScreenshotError.fileLoadFailed(url)
        }
        guard let img = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else {
            throw ScreenshotError.fileLoadFailed(url)
        }
        let w = img.width
        let h = img.height
        return try writeToDisk(
            img,
            mode: .crosshair,
            origin: .fullscreen,
            rect: CGRect(x: 0, y: 0, width: w, height: h),
            screenIndex: 0
        )
    }

    /// Discover all visible windows. Used by the window-highlight overlay.
    public func enumerateWindows() -> [WindowDescriptor] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return infoList.compactMap { dict -> WindowDescriptor? in
            guard let idNumber = dict[kCGWindowNumber as String] as? UInt32 else { return nil }
            guard let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            let layer = dict[kCGWindowLayer as String] as? Int ?? 0
            let alpha = dict[kCGWindowAlpha as String] as? Double ?? 1.0
            let onScreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? false
            return WindowDescriptor(
                id: idNumber,
                name: dict[kCGWindowName as String] as? String,
                ownerName: dict[kCGWindowOwnerName as String] as? String,
                bounds: bounds,
                layer: layer,
                alpha: alpha,
                isOnScreen: onScreen
            )
        }
    }

    // MARK: - Helpers

    /// Writes `cgImage` to disk as PNG under the temp directory, then returns
    /// a `CapturedImage` referencing the file URL.
    @discardableResult
    public func writeToDisk(
        _ cgImage: CGImage,
        mode: CaptureMode,
        origin: CapturedImage.Origin,
        rect: CGRect,
        screenIndex: Int
    ) throws -> CapturedImage {
        let url = try persist(cgImage: cgImage)

        return CapturedImage(
            mode: mode,
            origin: origin,
            rect: rect,
            fileURL: url,
            screenIndex: screenIndex
        )
    }

    private func persist(cgImage: CGImage) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Textractor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
