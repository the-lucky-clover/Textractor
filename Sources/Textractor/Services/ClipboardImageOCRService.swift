import AppKit
import Combine
import Vision
import CoreGraphics

/// Monitors the system pasteboard for image content and automatically runs OCR
/// on copied images, surfacing the result in the toast. This enables a workflow
/// where users copy a screenshot or image from any app and get text extraction
/// without manually triggering a capture.
///
/// Disabled by default (`clipboardImageOCR` setting). When enabled, the service
/// polls the pasteboard change count and processes any new image copied.
@MainActor
public final class ClipboardImageOCRService: ObservableObject {

    public static let shared = ClipboardImageOCRService()

    /// Published state for UI binding.
    @Published public private(set) var lastProcessedText: String?
    @Published public private(set) var isProcessing: Bool = false
    @Published public private(set) var lastConfidence: Float?

    private var lastChangeCount: Int = 0
    private var pollTimer: Timer?
    private var isEnabled: Bool = false
    private weak var coordinator: AppCoordinator?

    /// Polling interval in seconds. Slightly longer than typical paste latency.
    private let pollInterval: TimeInterval = 0.5

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Public API

    /// Configure the service with the app coordinator and start/stop based on setting.
    public func configure(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        updateEnabledState()
    }

    /// Update enabled state based on the current settings value.
    public func updateEnabledState() {
        let shouldEnable = coordinator?.appState.settings.clipboardImageOCR ?? false
        if shouldEnable != isEnabled {
            isEnabled = shouldEnable
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    /// Force-process the current pasteboard image (for manual trigger).
    public func processCurrentClipboard() async {
        await processIfNeeded(force: true)
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        stopMonitoring() // Ensure clean state
        lastChangeCount = NSPasteboard.general.changeCount

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkPasteboard()
            }
        }
        LoggerService.shared.info("ClipboardImageOCR: monitoring started")
    }

    private func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        LoggerService.shared.info("ClipboardImageOCR: monitoring stopped")
    }

    private func checkPasteboard() async {
        guard isEnabled else { return }

        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        await processIfNeeded(force: false)
    }

    // MARK: - OCR Processing

    private func processIfNeeded(force: Bool) async {
        guard let coordinator = coordinator else { return }
        guard !isProcessing else { return }

        let pasteboard = NSPasteboard.general

        // Check for image types
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("com.compuserve.gif")
        ]

        guard force || imageTypes.contains(where: { pasteboard.types?.contains($0) == true }) else {
            return
        }

        // Read image from pasteboard
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            return
        }

        await performOCR(on: image, coordinator: coordinator)
    }

    private func performOCR(on image: NSImage, coordinator: AppCoordinator) async {
        isProcessing = true
        defer { isProcessing = false }

        // Convert NSImage to CGImage for Vision
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            LoggerService.shared.warning("ClipboardImageOCR: failed to convert NSImage to CGImage")
            return
        }

        // Save to temp file — the pipeline requires a fileURL for loadCGImage
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-\(UUID().uuidString).png")

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            LoggerService.shared.warning("ClipboardImageOCR: failed to create PNG from clipboard image")
            return
        }

        do {
            try pngData.write(to: tempURL)
        } catch {
            LoggerService.shared.error("ClipboardImageOCR: failed to write temp image: \(error.localizedDescription)")
            return
        }

        // Build a CapturedImage for the pipeline - use .crosshair mode with .clipboard origin
        let capturedImage = CapturedImage(
            id: UUID(),
            mode: .crosshair,
            origin: .clipboard,
            rect: CGRect(origin: .zero, size: CGSize(width: cgImage.width, height: cgImage.height)),
            fileURL: tempURL,
            capturedAt: Date()
        )

        // Run the OCR pipeline
        await coordinator.runPipeline(for: capturedImage)

        // Update published state
        if let analysis = coordinator.appState.lastAnalysis {
            lastProcessedText = analysis.cleanedText
            lastConfidence = coordinator.appState.lastOCR?.averageConfidence
        } else if let ocr = coordinator.appState.lastOCR {
            lastProcessedText = ocr.joinedText
            lastConfidence = ocr.averageConfidence
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
    }

    deinit {
        pollTimer?.invalidate()
    }
}

// MARK: - Confidence Display Helpers

extension ClipboardImageOCRService {

    /// Returns a human-readable confidence level string.
    public var confidenceLevel: ConfidenceLevel {
        guard let conf = lastConfidence else { return .unknown }
        switch conf {
        case 0.9...1.0: return .excellent
        case 0.75..<0.9: return .good
        case 0.5..<0.75: return .fair
        default: return .poor
        }
    }

    public enum ConfidenceLevel: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case unknown = "Unknown"

        public var color: NSColor {
            switch self {
            case .excellent: return .systemGreen
            case .good: return .systemTeal
            case .fair: return .systemOrange
            case .poor: return .systemRed
            case .unknown: return .systemGray
            }
        }
    }
}