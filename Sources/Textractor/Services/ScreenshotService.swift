import AppKit
import AVFoundation
import CoreGraphics
import CoreImage
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Errors thrown by `ScreenshotService`.
public enum ScreenshotError: LocalizedError {
    case permissionDenied
    case noDisplay
    case noWindow
    case imageCreationFailed
    case fileLoadFailed(URL)
    case encodingFailed
    case continuityCameraNotAvailable
    case videoCaptureFailed
    case noCameraInput
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
        case .videoCaptureFailed: return "Video capture failed. Ensure camera access is granted."
        case .noCameraInput: return "No camera input detected."
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
/// Inherits `NSObject` so the instance can act as a delegate for
/// `AVCaptureVideoDataOutputSampleBufferDelegate` (used to stream frames
/// from the built-in camera and from any Continuity Camera iPhone/iPad).
public final class ScreenshotService: NSObject {

    public static let shared = ScreenshotService()

    private override init() { super.init() }

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

        let screens = NSScreen.screens
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

    /// Capture a single window by id via ScreenCaptureKit's
    /// `desktopIndependentWindow` content filter.
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
            telemetryEnabled: TelemetryService.shared.isEnabled
        )

        let content = try await SCShareableContent.current
        guard let scWin = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenshotError.noWindow
        }
        let filter = SCContentFilter(desktopIndependentWindow: scWin)
        let img = try await captureCGImage(filter: filter)
        let captured = try writeToDisk(img, mode: .window, origin: .window, rect: window.bounds, screenIndex: 0)
        return (captured, window)
    }

    /// Capture all displays. Returns one `CapturedImage` per display with the
    /// full surface of each (not just a cursor box — the previous 40×40 box
    /// didn't reflect the "Full Screen" label users see in the menu).
    public func captureFullScreen() async throws -> [CapturedImage] {
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

    // MARK: - Live Video Capture for OCR

    /// Starts a live video capture session from the default continuity / built-in camera.
    /// Returns an `AsyncThrowingStream` of `CapturedImage`s suitable for continuous OCR.
    /// Call `stopVideoCapture()` to end the session.
    private var videoCaptureSession: AVCaptureSession?
    private var videoCaptureOutput: AVCaptureVideoDataOutput?
    private var videoCaptureQueue = DispatchQueue(label: "textractor.video.capture")
    private var videoCaptureContinuation: AsyncThrowingStream<CapturedImage, Error>.Continuation?

    public func startVideoCapture() async throws -> AsyncThrowingStream<CapturedImage, Error> {
        LoggerService.shared.info("Starting live video capture")

        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw ScreenshotError.permissionDenied
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        // Find any video device — on macOS:
        //   `.external` ⇢ Continuity Camera (iPhone / iPad) AND USB cams
        //   `.builtInWideAngleCamera` ⇢ FaceTime / built-in Mac camera
        // `.builtInTrueDepthCamera` is iOS-only and unavailable on macOS.
        let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .external,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .unspecified
        ).devices.first

        guard let camera = device else { throw ScreenshotError.noCameraInput }
        let input = try AVCaptureDeviceInput(device: camera)

        session.addInput(input)

        // Use AVCaptureVideoDataOutput so we get per-frame CMSampleBuffers
        // for OCR streaming — AVCapturePhotoOutput is one-shot snapshots.
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: videoCaptureQueue)
        session.addOutput(output)

        videoCaptureSession = session
        videoCaptureOutput = output

        session.startRunning()

        return AsyncThrowingStream<CapturedImage, Error> { continuation in
            videoCaptureContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stopVideoCapture()
            }
        }
    }

    public func stopVideoCapture() {
        LoggerService.shared.info("Stopping live video capture")
        videoCaptureSession?.stopRunning()
        videoCaptureSession = nil
        videoCaptureOutput = nil
        videoCaptureContinuation?.finish()
        videoCaptureContinuation = nil
    }

    /// Helper: read a captured CMSampleBuffer into a `CapturedImage` and emit.
    fileprivate func handleVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let continuation = videoCaptureContinuation else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let width = cgImage.width
        let height = cgImage.height
        do {
            let captured = try writeToDisk(
                cgImage,
                mode: .crosshair,
                origin: .video,
                rect: CGRect(x: 0, y: 0, width: width, height: height),
                screenIndex: 0
            )
            continuation.yield(captured)
        } catch {
            continuation.yield(with: .failure(error))
        }
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
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ScreenshotService: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handleVideoFrame(sampleBuffer)
    }
}
