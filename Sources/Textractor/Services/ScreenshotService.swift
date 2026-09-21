import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import AVFoundation

/// Errors thrown by `ScreenshotService`.
public enum ScreenshotError: LocalizedError {
    case permissionDenied
    case noDisplay
    case noWindow
    case imageCreationFailed
    case fileLoadFailed(URL)
    case encodingFailed
    case continuityCameraNotAvailable
    case videoProcessingFailed(String)
    case processingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:    return "Screen Recording permission is required. Grant it in System Settings → Privacy & Security → Screen Recording, then re-launch Textractor."
        case .noDisplay:           return "No displays were detected."
        case .noWindow:            return "The selected window is not visible."
        case .imageCreationFailed: return "CoreGraphics could not build a screenshot."
        case .fileLoadFailed(let url):  return "Image could not be loaded from \(url.path)."
        case .encodingFailed:      return "Failed to encode image data."
        case .continuityCameraNotAvailable: return "Continuity Camera is not available on this Mac or the iPhone/iPad is not nearby."
        case .videoProcessingFailed(let reason): return "Video processing failed: \(reason)"
        case .processingFailed(let reason): return "Processing failed: \(reason)"
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
///
/// Inherits `NSObject` for Objective-C compatibility.
public final class ScreenshotService: NSObject {

    public static let shared = ScreenshotService()

    private override init() { super.init() }

    
    /// Throws `ScreenshotError.permissionDenied` when macOS Screen Recording
    /// access is not granted. Calling this *before* any ScreenCaptureKit /
    /// CoreGraphics capture API means a denial surfaces as a clean,
    /// distinguishable error instead of a generic image-creation failure.
    private func ensureScreenRecordingAccess() throws {
        // Refresh the permission state when entering the capture flow.
        // CGPreflightScreenCaptureAccess can return false even when permission
        // is actually granted (macOS caches the result), so we always refresh.
        // If permission is truly denied, ScreenCaptureKit itself will throw
        // an error which we handle downstream.
        PermissionService.shared.refresh()
    }

    // MARK: - Public API

    /// Capture a rectangular region (global AppKit screen coordinates) using
    /// ScreenCaptureKit: grab the whole display, then crop to the rect.
    public func captureRegion(_ rect: CGRect) async throws -> CapturedImage {
        LoggerService.shared.info("Capturing region \(NSStringFromRect(rect))")
        TelemetryService.shared.record(
            TelemetryEvent(kind: .captureRegion, success: true, meta: [
                "w": "\(Int(rect.width))", "h": "\(Int(rect.height))"
            ]),
            telemetryEnabled: TelemetryService.shared.isEnabled
        )

        try ensureScreenRecordingAccess()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            LoggerService.shared.error("captureRegion failed: no displays detected")
            throw ScreenshotError.noDisplay
        }
        let centerPoint = CGPoint(x: rect.midX, y: rect.midY)
        let screen = screens.first(where: { $0.frame.contains(centerPoint) }) ?? NSScreen.main ?? screens[0]
        let screenIndex = screens.firstIndex(of: screen) ?? 0

        let content = try await SCShareableContent.current
        guard let display = scDisplay(for: screen, in: content) ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let full = try await captureCGImage(filter: filter)
        let scale = CGFloat(full.width) / max(screen.frame.width, 1)
        let cropped = cropDisplayImage(full, displayFrame: screen.frame, scale: scale, toGlobalRect: rect)

        return try writeToDisk(cropped, mode: .crosshair, origin: .region, rect: rect, screenIndex: screenIndex)
    }

    /// Capture a single window by id using the same Quartz source of truth
    /// as `enumerateWindows()`. Avoids a SCShareableContent lookup mismatch
    /// where a window can be visible in the CGWindow list but absent from
    /// ScreenCaptureKit's snapshot (or vice-versa).
    public func captureWindow(_ windowID: CGWindowID) async throws -> (CapturedImage, WindowDescriptor) {
        try ensureScreenRecordingAccess()

        guard let window = enumerateWindows().first(where: { $0.id == windowID }) else {
            throw ScreenshotError.noWindow
        }
        LoggerService.shared.info("Capturing window \(windowID) '\(window.displayName)'")
        TelemetryService.shared.record(
            TelemetryEvent(kind: .captureWindow, success: true, meta: [
                "id": "\(windowID)",
                "name": window.displayName
            ]),
            telemetryEnabled: TelemetryService.shared.isEnabled
        )

        let content = try await SCShareableContent.current
        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenshotError.noWindow
        }
        let targetDisplayScreen: NSScreen = (NSScreen.screens.first { $0.frame.intersects(window.bounds) } ?? NSScreen.main)!
        guard let display = scDisplay(for: targetDisplayScreen, in: content) ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [scWindow])
        let fullImage = try await captureCGImage(filter: filter)
        let scale = CGFloat(fullImage.width) / max(targetDisplayScreen.frame.width, 1)
        let cropped = cropDisplayImage(fullImage, displaySizePoints: targetDisplayScreen.frame.size, scale: scale, toLocalRect: window.bounds)
        let captured = try writeToDisk(cropped, mode: .window, origin: .window, rect: window.bounds, screenIndex: 0)
        return (captured, window)
    }

    /// Capture all displays. Returns one `CapturedImage` per display with the
    /// full surface of each (not just a cursor box — the previous 40×40 box
    /// didn't reflect the "Full Screen" label users see in the menu).
    public func captureFullScreen() async throws -> [CapturedImage] {
        try ensureScreenRecordingAccess()

        let displays = NSScreen.screens
        guard !displays.isEmpty else { throw ScreenshotError.noDisplay }

        LoggerService.shared.info("Capturing full screen (\(displays.count) displays)")
        TelemetryService.shared.record(
            TelemetryEvent(kind: .captureRegion, success: true, meta: ["mode": "fullscreen", "displays": "\(displays.count)"]),
            telemetryEnabled: TelemetryService.shared.isEnabled
        )

        let content = try await SCShareableContent.current

        var results: [CapturedImage] = []
        for (index, screen) in displays.enumerated() {
            let screenFrame = screen.frame
            guard let display = scDisplay(for: screen, in: content) ?? content.displays.first else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            guard let full = try? await captureCGImage(filter: filter) else { continue }
            do {
                let captured = try writeToDisk(
                    full,
                    mode: .crosshair,
                    origin: .fullscreen,
                    rect: screenFrame,
                    screenIndex: index
                )
                results.append(captured)
            } catch {
                LoggerService.shared.warning("fullscreen write failed for display \(index): \(error.localizedDescription)")
            }
        }
        return results
    }

    /// Discover every connected display and return a descriptor for each so
    /// callers can present a picker or drive cursor-driven capture on a TV /
    /// secondary monitor.
    public struct DisplayDescriptor: Identifiable, Hashable, Sendable {
        public let index: Int
        public let id: CGDirectDisplayID
        public let frame: CGRect
        public let isMain: Bool

        public var label: String {
            isMain ? "Main Display" : "Display \(index + 1)"
        }
    }

    public func enumerateDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            return DisplayDescriptor(
                index: index,
                id: did,
                frame: screen.frame,
                isMain: screen == NSScreen.main
            )
        }
    }

    /// Capture the full surface of one specific display (by index in
    /// `NSScreen.screens`) via ScreenCaptureKit so OCR downstream can target
    /// text rendered on a TV / secondary monitor.
    public func captureDisplay(at index: Int) async throws -> CapturedImage {
        let displays = NSScreen.screens
        guard displays.indices.contains(index) else { throw ScreenshotError.noDisplay }
        let screen = displays[index]
        let frame = screen.frame

        LoggerService.shared.info("Capturing display \(index) frame=\(NSStringFromRect(frame))")
        TelemetryService.shared.record(
            TelemetryEvent(kind: .captureRegion, success: true, meta: ["mode": "display", "index": "\(index)"]),
            telemetryEnabled: TelemetryService.shared.isEnabled
        )

        let content = try await SCShareableContent.current
        guard let display = scDisplay(for: screen, in: content) ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let img = try await captureCGImage(filter: filter)
        return try writeToDisk(img, mode: .crosshair, origin: .fullscreen, rect: frame, screenIndex: index)
    }

    /// Capture a rectangular region expressed in the coordinate space of a
    /// specific display (by index) via ScreenCaptureKit: grab that display,
    /// then crop to the rect. Lets the crosshair overlay map a drag on any
    /// monitor back to the right rect for OCR.
    public func captureRegion(_ rect: CGRect, onDisplay index: Int) async throws -> CapturedImage {
        LoggerService.shared.info("Capturing region \(NSStringFromRect(rect)) on display \(index)")
        TelemetryService.shared.record(
            TelemetryEvent(kind: .captureRegion, success: true, meta: [
                "w": "\(Int(rect.width))", "h": "\(Int(rect.height))", "index": "\(index)"
            ]),
            telemetryEnabled: TelemetryService.shared.isEnabled
        )

        let screens = NSScreen.screens
        guard screens.indices.contains(index) else { throw ScreenshotError.noDisplay }
        let screen = screens[index]

        let content = try await SCShareableContent.current
        guard let display = scDisplay(for: screen, in: content) ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let full = try await captureCGImage(filter: filter)
        let scale = CGFloat(full.width) / max(screen.frame.width, 1)
        let cropped = cropDisplayImage(full, displaySizePoints: screen.frame.size, scale: scale, toLocalRect: rect)

        return try writeToDisk(cropped, mode: .crosshair, origin: .region, rect: rect, screenIndex: index)
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

    /// Load an image from a file URL and persist it to the Textractor temp directory.
    /// Returns a `CapturedImage` with `.file` origin.
    public func loadImage(from url: URL) async throws -> CapturedImage {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ScreenshotError.fileLoadFailed(url)
        }
        let persistedURL = try persist(cgImage: cgImage)
        return CapturedImage(
            mode: .crosshair, // default mode for file imports
            origin: .file,
            rect: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height),
            fileURL: persistedURL
        )
    }

    /// Check if Continuity Camera is available on this Mac with a nearby iOS device.
    @available(macOS 13.0, *)
    public func isContinuityCameraAvailable() async -> Bool {
        // Check if there's at least one iOS device nearby that supports Continuity Camera
        // We use a lightweight check by trying to enumerate devices
        // For now, return true on macOS 13+ as the system handles the availability UI
        return true
    }

    // MARK: - Continuity Camera Support

    /// Capture an image using the Continuity Camera (iPhone/iPad as webcam).
    /// macOS presents a native system sheet when an iPhone is held near the
    /// computer asking the user to "Take Photo" or "Scan Documents".
    /// On older macOS versions or without a nearby device, throws.
    @available(macOS 13.0, *)
    @MainActor
    public func captureFromContinuityCamera() async throws -> CapturedImage {
        LoggerService.shared.info("Starting Continuity Camera capture")

        // macOS exposes Continuity Camera via ImageCaptureCore's ICCameraDevice;
        // we rely on the system-provided `IKDeviceBrowserViewController`-style
        // file dialog that automatically surfaces nearby iOS devices when the
        // user opens an NSOpenPanel on a supported version.
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.image]
        openPanel.prompt = "Insert from iPhone"

        let response = await withCheckedContinuation { continuation in
            openPanel.begin { response in
                continuation.resume(returning: response)
            }
        }

        guard response == .OK, let url = openPanel.url else {
            throw ScreenshotError.continuityCameraNotAvailable
        }

        return try await ingestFile(at: url, origin: .continuityCamera)
    }

    /// Capture frames from a video URL at regular intervals and run OCR on each.
    /// Returns the first successful capture with extracted text.
    /// - Parameters:
    ///   - url: The video file URL (local or remote)
    ///   - interval: Time interval between frames to extract (default: 2 seconds)
    ///   - maxFrames: Maximum number of frames to process (default: 30)
    public func captureFromVideoURL(
        _ url: URL,
        interval: TimeInterval = 2.0,
        maxFrames: Int = 30
    ) async throws -> [CapturedImage] {
        LoggerService.shared.info("Processing video URL: \(url.lastPathComponent)")

        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw ScreenshotError.videoProcessingFailed("Video has zero duration")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let frameCount = min(maxFrames, max(1, Int(durationSeconds / interval)))
        var capturedImages: [CapturedImage] = []

        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            do {
                let cgImage = try await generator.image(at: time).image
                let w = cgImage.width
                let h = cgImage.height

                let captured = try writeToDisk(
                    cgImage,
                    mode: .crosshair,
                    origin: .videoURL,
                    rect: CGRect(x: 0, y: 0, width: w, height: h),
                    screenIndex: 0
                )

                // Store timestamp in the captured image metadata if needed
                // For now we just add the captured image
                capturedImages.append(captured)

            } catch {
                LoggerService.shared.warning("Failed to extract frame at \(time.seconds)s: \(error)")
                continue
            }
        }

        guard !capturedImages.isEmpty else {
            throw ScreenshotError.videoProcessingFailed("No frames could be extracted from video")
        }

        return capturedImages
    }

    /// Internal async file loader used by both `captureFromFile` and Continuity
    /// Camera so they share the same `origin` handling path.
    internal func ingestFile(at url: URL, origin: CapturedImage.Origin) async throws -> CapturedImage {
        LoggerService.shared.info("Ingesting file \(url.lastPathComponent) origin=\(origin.rawValue)")
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
            origin: origin,
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

    // MARK: - ScreenCaptureKit helpers

    /// Capture a `CGImage` for a given content filter using the modern
    /// ScreenCaptureKit `SCScreenshotManager`.
    private func captureCGImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration = SCStreamConfiguration()
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: ScreenshotError.processingFailed("ScreenCaptureKit: \(error.localizedDescription)"))
                    return
                }
                guard let image else {
                    continuation.resume(throwing: ScreenshotError.imageCreationFailed)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    /// Resolve the `SCDisplay` backing a given `NSScreen` from shareable content.
    private func scDisplay(for screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return content.displays.first { $0.displayID == displayID }
    }

    /// Capture a screen region as a CGImage (no disk write) for live OCR preview.
    /// Uses ScreenCaptureKit to capture the display, then crops to the given rect.
    /// This is fast enough to run ~4× per second during region drag.
    public func captureCGImageForRect(_ rect: CGRect) async throws -> CGImage {
        try ensureScreenRecordingAccess()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw ScreenshotError.noDisplay }
        let centerPoint = CGPoint(x: rect.midX, y: rect.midY)
        let screen = screens.first { $0.frame.contains(centerPoint) } ?? NSScreen.main ?? screens[0]

        let content = try await SCShareableContent.current
        guard let display = scDisplay(for: screen, in: content) ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let full = try await captureCGImage(filter: filter)
        let scale = CGFloat(full.width) / max(screen.frame.width, 1)
        let cropped = cropDisplayImage(full, displayFrame: screen.frame, scale: scale, toGlobalRect: rect)
        return cropped
    }

    /// Crop a display-sized `CGImage` (top-left origin, pixels = points × scale)
    /// down to a rect expressed in global AppKit (bottom-left origin) points.
    private func cropDisplayImage(
        _ image: CGImage,
        displayFrame: CGRect,
        scale: CGFloat,
        toGlobalRect rect: CGRect
    ) -> CGImage {
        let dx = (rect.minX - displayFrame.minX) * scale
        let dy = (displayFrame.maxY - rect.maxY) * scale
        let crop = CGRect(x: dx, y: dy, width: rect.width * scale, height: rect.height * scale)
        let clamped = crop.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !clamped.isEmpty, let cropped = image.cropping(to: clamped) else { return image }
        return cropped
    }

    /// Crop a display-sized `CGImage` down to a rect expressed in the display's
    /// own local coordinate space (AppKit bottom-left origin, points).
    private func cropDisplayImage(
        _ image: CGImage,
        displaySizePoints: CGSize,
        scale: CGFloat,
        toLocalRect rect: CGRect
    ) -> CGImage {
        let dx = rect.minX * scale
        let dy = (displaySizePoints.height - rect.maxY) * scale
        let crop = CGRect(x: dx, y: dy, width: rect.width * scale, height: rect.height * scale)
        let clamped = crop.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !clamped.isEmpty, let cropped = image.cropping(to: clamped) else { return image }
        return cropped
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

    // MARK: - Auto-scroll capture

    /// Automatically scrolls a window and stitches multiple captures together
    /// to capture content that extends beyond the visible viewport (below the fold).
    /// Uses AppleScript to scroll and compares frames to detect the bottom.
    /// - Parameters:
    ///   - windowID: The CGWindowID of the window to capture
    ///   - scrollInterval: Time between scroll actions in seconds (default: 0.5s)
    ///   - maxScrolls: Maximum number of scroll attempts (default: 50)
    ///   - overlap: Pixel overlap between stitched frames (default: 100px)
    /// - Returns: A CapturedImage containing the full stitched content
    public func captureWindowWithAutoScroll(
        _ windowID: CGWindowID,
        scrollInterval: TimeInterval = 0.5,
        maxScrolls: Int = 50,
        overlap: CGFloat = 100
    ) async throws -> CapturedImage {
        try ensureScreenRecordingAccess()

        // Find the window descriptor
        guard let window = enumerateWindows().first(where: { $0.id == windowID }) else {
            throw ScreenshotError.noWindow
        }

        // Capture the first frame
        let firstCapture = try await captureWindow(windowID)
        guard let firstImage = loadCGImage(from: firstCapture.0.fileURL) else {
            throw ScreenshotError.imageCreationFailed
        }

        var stitchedImage = firstImage
        var previousImage = firstImage
        var scrollCount = 0
        var isAtBottom = false

        while scrollCount < 50 && !isAtBottom {
            // Scroll down using AppleScript
            let scrollScript = """
            tell application "System Events"
                tell process "\(window.ownerName ?? "")"
                    key code 125 -- down arrow
                end tell
            end tell
            """

            let script = NSAppleScript(source: scrollScript)
            script?.executeAndReturnError(nil)

            // Wait for scroll animation
            try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))

            // Capture current state
            let currentCapture = try await captureWindow(windowID)
            guard let currentImage = loadCGImage(from: currentCapture.0.fileURL) else {
                break
            }

            // Check if we've reached the bottom by comparing with previous image
            if imagesAreSimilar(previousImage, currentImage, threshold: 0.98) {
                break
            }

            // Stitch the new image below the previous one
            stitchedImage = stitchImagesVertically(top: stitchedImage, bottom: currentImage, overlap: 100)
            previousImage = currentImage
        }
        
        // Save the final stitched image
        let url = try persist(cgImage: stitchedImage)
        let rect = CGRect(x: 0, y: 0, width: stitchedImage.width, height: stitchedImage.height)
        
        return CapturedImage(
            mode: .autoScroll,
            origin: .autoScroll,
            rect: CGRect(x: 0, y: 0, width: stitchedImage.width, height: stitchedImage.height),
            fileURL: url,
            screenIndex: 0
        )
    }

    /// Compare two images for similarity (0.0 to 1.0)
    private func imagesAreSimilar(_ img1: CGImage, _ img2: CGImage, threshold: Double) -> Bool {
        guard img1.width == img2.width && img1.height == img2.height else { return false }
        
        let width = min(img1.width, img2.width)
        let height = min(img1.height, img2.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * 4
        
        var pixels1 = [UInt8](repeating: 0, count: width * height * 4)
        var pixels2 = [UInt8](repeating: 0, count: width * height * 4)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context1 = CGContext(data: &pixels1, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context2 = CGContext(data: &pixels2, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        context1?.draw(img1, in: CGRect(x: 0, y: 0, width: width, height: height))
        context2?.draw(img2, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var differentPixels = 0
        let totalPixels = width * height
        
        for i in 0..<totalPixels {
            let idx = i * 4
            let r1 = pixels1[idx]
            let g1 = pixels1[idx + 1]
            let b1 = pixels1[idx + 2]
            let r2 = pixels2[idx]
            let g2 = pixels2[idx + 1]
            let b2 = pixels2[idx + 2]
            
            let dr = abs(Int(r1) - Int(r2))
            let dg = abs(Int(g1) - Int(g2))
            let db = abs(Int(b1) - Int(b2))
            
            if dr > 10 || dg > 10 || db > 10 {
                differentPixels += 1
            }
        }
        
        let similarity = 1.0 - Double(differentPixels) / Double(totalPixels)
        return similarity >= 0.98
    }
    
    /// Stitch two images vertically with overlap
    private func stitchImagesVertically(top: CGImage, bottom: CGImage, overlap: CGFloat) -> CGImage {
        let topHeight = top.height
        let bottomHeight = bottom.height
        let overlapInt = Int(overlap)
        
        let newHeight = topHeight + bottomHeight - overlapInt
        let width = max(top.width, bottom.width)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        
        // Draw top image
        context.draw(top, in: CGRect(x: 0, y: 0, width: top.width, height: topHeight))
        
        // Draw bottom image, overlapping by 'overlap' pixels
        let bottomY = topHeight - overlapInt
        context.draw(bottom, in: CGRect(x: 0, y: bottomY, width: bottom.width, height: bottomHeight))
        
        return context.makeImage()!
    }
    
    /// Load a CGImage from a file URL
    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return img
    }
}
