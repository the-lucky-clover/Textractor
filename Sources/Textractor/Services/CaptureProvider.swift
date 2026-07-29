import Foundation
import CoreGraphics
import SwiftUI
import AVFoundation

/// A unified protocol for all capture sources in Textractor.
/// Each provider handles a specific capture mode and returns a `CapturedImage`.
@MainActor
public protocol CaptureProvider: Sendable {
    /// Unique identifier for this capture provider.
    var id: String { get }
    
    /// Human-readable name for UI.
    var name: String { get }
    
    /// System symbol for toolbar/menu representation.
    var symbolName: String { get }
    
    /// Short description shown in tooltips.
    var shortDescription: String { get }
    
    /// Whether this provider is currently available (e.g., permissions granted).
    var isAvailable: Bool { get async }
    
    /// Capture an image and return a `CapturedImage` ready for processing.
    /// - Returns: A `CapturedImage` with the captured file and metadata.
    func capture() async throws -> CapturedImage
    
    /// Optional: cancel any in-progress capture.
    func cancel() async
}

/// Default implementations.
public extension CaptureProvider {
    func cancel() async { }
}

/// Standard capture modes provided by the system.
public enum CaptureProviderType: String, CaseIterable, Identifiable, Sendable {
    case region = "region"
    case window = "window"
    case fullscreen = "fullscreen"
    case video = "video"
    case continuityCamera = "continuityCamera"
    case file = "file"
    case camera = "camera"
    case screenRecording = "screenRecording"
    case scrollCapture = "scrollCapture"
    
    public var id: String { rawValue }
    
    public var name: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window"
        case .fullscreen: return "Full Screen"
        case .video: return "Video"
        case .continuityCamera: return "iPhone / iPad Camera"
        case .file: return "Import File"
        case .camera: return "Built-in Camera"
        case .screenRecording: return "Screen Recording"
        case .scrollCapture: return "Scroll Capture"
        }
    }
    
    public var symbolName: String {
        switch self {
        case .region: return "viewfinder"
        case .window: return "macwindow"
        case .fullscreen: return "macwindow.on.rectangle"
        case .video: return "video"
        case .continuityCamera: return "camera.fill"
        case .file: return "doc.badge.plus"
        case .camera: return "camera.macro"
        case .screenRecording: return "record.circle"
        case .scrollCapture: return "doc.text.fill.viewfinder"
        }
    }
}

/// Registry for all available capture providers.
/// Allows plugins and built-in providers to be discovered dynamically.
@MainActor
public final class CaptureProviderRegistry: ObservableObject {
    public static let shared = CaptureProviderRegistry()
    
    @Published private(set) var providers: [CaptureProvider] = []
    
    private init() { }
    
    public func register(_ provider: CaptureProvider) {
        providers.append(provider)
    }
    
    public func unregister(id: String) {
        providers.removeAll { $0.id == id }
    }
    
    public func provider(for type: CaptureProviderType) -> CaptureProvider? {
        providers.first { $0.id == type.rawValue }
    }
    
    public var availableProviders: [CaptureProvider] {
        get async {
            var result: [CaptureProvider] = []
            for provider in providers {
                if await provider.isAvailable {
                    result.append(provider)
                }
            }
            return result
        }
    }
}

/// Default implementations for common capture providers.
/// These wrap the existing ScreenshotService functionality.
@MainActor
public struct BuiltInCaptureProviders {
    
    /// Provider for region (crosshair drag) capture.
    public final class RegionCaptureProvider: NSObject, CaptureProvider {
        public let id = "region"
        public let name = "Region"
        public let symbolName = "viewfinder"
        public let shortDescription = "Drag to select an area"
        
        private let screenshotService = ScreenshotService.shared
        private var currentRect: CGRect?
        
        public var isAvailable: Bool {
            get async {
                PermissionService.shared.screenRecordingGranted
            }
        }
        
        public func capture() async throws -> CapturedImage {
            guard let rect = currentRect else {
                throw ScreenshotError.noWindow
            }
            return try await screenshotService.captureRegion(rect)
        }
        
        /// Set the region rect before capture (called by overlay).
        public func setRegion(_ rect: CGRect) {
            self.currentRect = rect
        }
        
        public func cancel() async {
            currentRect = nil
        }
    }
    
    /// Provider for window click capture.
    public final class WindowCaptureProvider: NSObject, CaptureProvider {
        public let id = "window"
        public let name = "Window"
        public let symbolName = "macwindow"
        public let shortDescription = "Click a window to capture"
        
        private let screenshotService = ScreenshotService.shared
        private var targetWindowID: CGWindowID?
        
        public var isAvailable: Bool {
            get async {
                PermissionService.shared.screenRecordingGranted
            }
        }
        
        public func capture() async throws -> CapturedImage {
            guard let windowID = targetWindowID else {
                throw ScreenshotError.noWindow
            }
            let (captured, _) = try await screenshotService.captureWindow(windowID)
            return captured
        }
        
        public func setTargetWindow(_ windowID: CGWindowID) {
            self.targetWindowID = windowID
        }
        
        public func cancel() async {
            targetWindowID = nil
        }
    }
    
    /// Provider for full-screen capture.
    public final class FullScreenCaptureProvider: NSObject, CaptureProvider {
        public let id = "fullscreen"
        public let name = "Full Screen"
        public let symbolName = "macwindow.on.rectangle"
        public let shortDescription = "Capture entire screen"
        
        private let screenshotService = ScreenshotService.shared
        
        public var isAvailable: Bool {
            get async {
                PermissionService.shared.screenRecordingGranted
            }
        }
        
        public func capture() async throws -> CapturedImage {
            // Capture the main screen by default
            let screens = NSScreen.screens
            guard let screen = screens.first else {
                throw ScreenshotError.noDisplay
            }
            return try await screenshotService.captureRegion(screen.frame)
        }
    }
    
    /// Provider for importing image files.
    public final class FileImportProvider: NSObject, CaptureProvider {
        public let id = "file"
        public let name = "Import File"
        public let symbolName = "doc.badge.plus"
        public let shortDescription = "Import an image from disk"
        
        private let screenshotService = ScreenshotService.shared
        
        public var isAvailable: Bool { true }
        
        public func capture() async throws -> CapturedImage {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .pdf]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            
            guard await panel.beginSheetModal(for: NSApp.keyWindow!) == .OK,
                  let url = panel.url else {
                throw ScreenshotError.fileLoadFailed(URL(fileURLWithPath: ""))
            }
            
            return try await screenshotService.captureFromFile(at: url)
        }
    }
    
    /// Provider for Continuity Camera (iPhone/iPad).
    public final class ContinuityCameraProvider: NSObject, CaptureProvider {
        public let id = "continuityCamera"
        public let name = "iPhone / iPad Camera"
        public let symbolName = "camera.fill"
        public let shortDescription = "Take photo or scan with iPhone/iPad"
        
        private let screenshotService = ScreenshotService.shared
        
        public var isAvailable: Bool {
            get async {
                if #available(macOS 13.0, *) {
                    return true
                }
                return false
            }
        }
        
        public func capture() async throws -> CapturedImage {
            if #available(macOS 13.0, *) {
                return try await screenshotService.captureFromContinuityCamera()
            } else {
                throw ScreenshotError.continuityCameraNotAvailable
            }
        }
    }
    
    /// Provider for built-in camera capture.
    public final class BuiltInCameraProvider: NSObject, CaptureProvider {
        public let id = "camera"
        public let name = "Built-in Camera"
        public let symbolName = "camera.macro"
        public let shortDescription = "Capture from Mac camera"
        
        public var isAvailable: Bool {
            get async {
                // Check if camera is available and permission granted
                AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            }
        }
        
        public func capture() async throws -> CapturedImage {
            // Implementation will use AVCaptureSession
            throw ScreenshotError.processingFailed("Built-in camera capture not yet implemented")
        }
    }
    
    /// Provider for screen recording indexing.
    public final class ScreenRecordingProvider: NSObject, CaptureProvider {
        public let id = "screenRecording"
        public let name = "Screen Recording"
        public let symbolName = "record.circle"
        public let shortDescription = "Index a screen recording"
        
        public var isAvailable: Bool { true }
        
        public func capture() async throws -> CapturedImage {
            throw ScreenshotError.processingFailed("Screen recording indexing not yet implemented")
        }
    }
    
    /// Provider for scroll capture.
    public final class ScrollCaptureProvider: NSObject, CaptureProvider {
        public let id = "scrollCapture"
        public let name = "Scroll Capture"
        public let symbolName = "doc.text.fill.viewfinder"
        public let shortDescription = "Capture long scrolling content"
        
        public var isAvailable: Bool {
            get async {
                PermissionService.shared.screenRecordingGranted
            }
        }
        
        public func capture() async throws -> CapturedImage {
            throw ScreenshotError.processingFailed("Scroll capture not yet implemented")
        }
    }
    
    /// Convenience: all built-in providers.
    public static var all: [CaptureProvider] {
        [
            RegionCaptureProvider(),
            WindowCaptureProvider(),
            FullScreenCaptureProvider(),
            FileImportProvider(),
            ContinuityCameraProvider(),
            BuiltInCameraProvider(),
            ScreenRecordingProvider(),
            ScrollCaptureProvider()
        ]
    }
}