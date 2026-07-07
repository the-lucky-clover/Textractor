//
//  TextractorError.swift
//
//  Structured error model with severity, localized description, and recovery hints.
//
//

import Foundation

enum TextractorError: Error, LocalizedError {
    case screenCaptureFailed(String)
    case noDisplayDetected
    case ocrEngineUnavailable
    case ocrProcessingFailed(String)
    case noTextRecognized
    case lowConfidence(Double)
    case clipboardWriteFailed
    case hotkeyRegistrationFailed(UInt32)
    case permissionDenied(String)
    case imageTooSmall
    case imageCorrupted
    case timeoutExceeded
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .screenCaptureFailed(let detail):
            return "Screen capture failed: \(detail)"
        case .noDisplayDetected:
            return "No active display detected."
        case .ocrEngineUnavailable:
            return "On-device OCR engine unavailable. macOS 12.0+ required."
        case .ocrProcessingFailed(let detail):
            return "OCR processing error: \(detail)"
        case .noTextRecognized:
            return "No text was recognized in the selected region."
        case .lowConfidence(let confidence):
            return "Low confidence result (\(String(format: "%.0f%%", confidence * 100))). Text may be inaccurate."
        case .clipboardWriteFailed:
            return "Failed to write to clipboard."
        case .hotkeyRegistrationFailed(let keyCode):
            return "Failed to register hotkey (keyCode: \(keyCode))."
        case .permissionDenied(let permission):
            return "Permission denied: \(permission). Please grant access in System Settings."
        case .imageTooSmall:
            return "Selected region too small for reliable OCR."
        case .imageCorrupted:
            return "Captured image data is corrupted."
        case .timeoutExceeded:
            return "OCR processing timed out. Try a smaller region."
        case .unknown(let detail):
            return "Unknown error: \(detail)"
        }
    }

    var recoveryHint: String {
        switch self {
        case .screenCaptureFailed:
            return "Check Screen Recording permission in System Settings → Privacy & Security."
        case .noDisplayDetected:
            return "Ensure your display is connected and awake."
        case .ocrEngineUnavailable:
            return "Update to macOS 12.0 Monterey or later."
        case .ocrProcessingFailed:
            return "Try selecting a clearer, higher-contrast region."
        case .noTextRecognized:
            return "Select a region that contains visible text."
        case .lowConfidence:
            return "Auto-heal will attempt to correct common OCR mistakes. Try a higher-resolution selection."
        case .clipboardWriteFailed:
            return "Quit and relaunch Textractor. If the issue persists, check for conflicting clipboard managers."
        case .hotkeyRegistrationFailed:
            return "Another app may be using ⌘⇧2. Change the hotkey in Settings."
        case .permissionDenied(let perm):
            return "Open System Settings → Privacy & Security → \(perm) and enable Textractor."
        case .imageTooSmall:
            return "Drag a larger selection rectangle."
        case .imageCorrupted:
            return "Retry the capture. If persistent, restart your Mac."
        case .timeoutExceeded:
            return "Select a smaller, text-focused region."
        case .unknown:
            return "Retry the extraction. If the issue persists, check the error log."
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .noTextRecognized, .imageTooSmall, .lowConfidence:
            return .warning
        case .screenCaptureFailed, .ocrProcessingFailed, .timeoutExceeded, .imageCorrupted:
            return .error
        case .permissionDenied, .hotkeyRegistrationFailed, .ocrEngineUnavailable, .clipboardWriteFailed:
            return .critical
        case .noDisplayDetected:
            return .info
        case .unknown:
            return .error
        }
    }

    var canAutoHeal: Bool {
        switch self {
        case .lowConfidence, .noTextRecognized, .ocrProcessingFailed, .timeoutExceeded, .imageTooSmall:
            return true
        default:
            return false
        }
    }
}

enum ErrorSeverity {
    case info, warning, error, critical

    var color: String {
        switch self {
        case .info:     return "neonCyan"
        case .warning:  return "neonAmber"
        case .error:    return "neonRed"
        case .critical: return "neonMagenta"
        }
    }
}
