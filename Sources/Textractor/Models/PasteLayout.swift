import Foundation

/// Specifies how text should be laid out when pasted to the clipboard.
///
/// - `original`: Keep the OCR line breaks verbatim.
/// - `paragraphs`: Merge soft-wrapped lines into flowing paragraphs.
/// - `reconstruct`: Preserve detected table structure when available.
public enum PasteLayout: String, Codable, CaseIterable, Sendable {
    case original
    case paragraphs
    case reconstruct

    public var label: String {
        switch self {
        case .original:    return "Original layout"
        case .paragraphs:  return "Merge into paragraphs"
        case .reconstruct: return "Reconstruct tables"
        }
    }
}
