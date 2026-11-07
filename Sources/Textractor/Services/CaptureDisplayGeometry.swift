import AppKit

/// All inputs are AppKit global points, except explicitly named overlay/Quartz coordinates.
public enum CaptureDisplayGeometry {
    public static func displayIndex(at pointer: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(pointer) }
    }
    public static func overlayPoint(fromGlobal point: CGPoint, frame: CGRect) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }
    public static func globalRect(fromOverlay rect: CGRect, frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
    public static func overlayRect(fromQuartz rect: CGRect, frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX - frame.minX, y: rect.minY + frame.maxY - primaryHeight, width: rect.width, height: rect.height)
    }
    public static func pixelCrop(globalRect: CGRect, displayFrame: CGRect, imageSize: CGSize) -> CGRect? {
        guard displayFrame.width > 0, displayFrame.height > 0, imageSize.width > 0, imageSize.height > 0,
              globalRect.width > 0, globalRect.height > 0 else { return nil }
        let rect = globalRect.intersection(displayFrame)
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let sx = imageSize.width / displayFrame.width, sy = imageSize.height / displayFrame.height
        return CGRect(x: (rect.minX - displayFrame.minX) * sx, y: (displayFrame.maxY - rect.maxY) * sy,
                      width: rect.width * sx, height: rect.height * sy)
    }

}

/// Borderless capture windows must not be constrained onto the primary screen's visible area.
final class CaptureOverlayWindow: NSWindow {
    convenience init(frame: CGRect) {
        self.init(contentRect: frame, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        isOpaque = false; backgroundColor = .clear; acceptsMouseMovedEvents = true
        setFrame(frame, display: false)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
