import Foundation
import SwiftUI

/// User-selectable capture mode displayed by the crosshair overlay.
///
/// The crosshair overlay cycles through these modes with the SPACE key.
public enum CaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case crosshair // drag a rectangle
    case window    // click a window

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .crosshair: return "Crosshair"
        case .window:    return "Window"
        }
    }

    public var hint: String {
        switch self {
        case .crosshair: return "Drag a rectangle  •  SPACE → Window"
        case .window:    return "Hover highlights  •  click window  •  SPACE → Drag"
        }
    }

    public var symbolName: String {
        switch self {
        case .crosshair: return "viewfinder"
        case .window:    return "macwindow"
        }
    }
}
