import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Crosshair + Window overlay (one screen-filling NSWindow)
//
// Used both for the ⌘⇧2 hotkey and for the menubar "Capture Region / Window"
// actions. SPACE toggles mode; ESC cancels; RETURN accepts the selection.

public struct CaptureOverlayView: View {

    // MARK: Callbacks

    public typealias OnRegionCaptured = (CGRect) -> Void
    public typealias OnWindowCaptured = (CGWindowID) -> Void
    public typealias OnCancel = () -> Void

    let screen: NSScreen
    var initialMode: CaptureMode
    var onRegionCaptured: OnRegionCaptured
    var onWindowCaptured: OnWindowCaptured
    var onCancel: OnCancel

    // MARK: State

    @State private var mode: CaptureMode
    @State private var cursorPoint: CGPoint = .zero
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var hoveredWindow: WindowDescriptor?
    @State private var windows: [WindowDescriptor] = []

    public init(
        screen: NSScreen,
        initialMode: CaptureMode = .crosshair,
        onRegionCaptured: @escaping OnRegionCaptured,
        onWindowCaptured: @escaping OnWindowCaptured,
        onCancel: @escaping OnCancel
    ) {
        self.screen = screen
        self.initialMode = initialMode
        self.onRegionCaptured = onRegionCaptured
        self.onWindowCaptured = onWindowCaptured
        self.onCancel = onCancel
        self._mode = State(initialValue: initialMode)
    }

    // MARK: Geometry

    private let padding: CGFloat = 28
    private let screenFrame: CGRect = NSScreen.main?.frame ?? .zero

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Inverse scrim - darkens the WHOLE screen, but we leave the
                // captured selection bright via .blendMode(.difference).
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .overlay(selectionScrim(size: size))

                // Mode body
                switch mode {
                case .crosshair:
                    crosshairBody(size: size)
                case .window:
                    windowBody(size: size)
                }

                // Top status bar
                statusBar(size: size)
                    .frame(width: size.width, height: 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Coordinates readout
                if mode == .crosshair, let r = currentSelectionRect(size: size) {
                    rectReadout(r)
                        .position(x: r.maxX - 64, y: r.maxY + 22)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(size: size))
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    cursorPoint = p
                    updateHoveredWindow()
                case .ended:
                    hoveredWindow = nil
                }
            }
            .focusable(true)
            .onKeyPress(.space) {
                LoggerService.shared.info("[capture.key] SPACE pressed, was mode=\(mode.rawValue)")
                mode = (mode == .crosshair) ? .window : .crosshair
                hoveredWindow = nil
                LoggerService.shared.info("[capture.key] SPACE handled, now mode=\(mode.rawValue)")
                return .handled
            }
            .onKeyPress(.escape) {
                LoggerService.shared.info("[capture.key] ESC pressed")
                onCancel()
                return .handled
            }
            .onKeyPress(.return) {
                LoggerService.shared.info("[capture.key] RETURN pressed, mode=\(mode.rawValue)")
                handleAccept(size: size)
                return .handled
            }
            .onAppear {
                LoggerService.shared.info("[capture.ui] onAppear; windows=\(ScreenshotService.shared.enumerateWindows().filter { $0.isCaptureEligible }.count)")
                windows = ScreenshotService.shared.enumerateWindows().filter { $0.isCaptureEligible }
            }
        }
        .background(Color.black.opacity(0.001).ignoresSafeArea())
    }

    // MARK: - Status bar

    @ViewBuilder private func statusBar(size: CGSize) -> some View {
        HStack(spacing: 14) {
            BeakerIcon(size: 18, glyphs: ["T"], style: .template)
            Text("Textractor Capture")
                .font(NeonFont.monoCaps(11))
                .foregroundStyle(.primary)
            Spacer()
            Text(mode == .crosshair ? "Region  •  drag" : "Window  •  click")
                .font(NeonFont.monoCaps(11))
                .foregroundStyle(mode == .crosshair ? NeonPalette.cyberCyan : NeonPalette.magentaNeon)
            Text("·").foregroundStyle(.secondary)
            Text("SPACE: switch").font(NeonFont.monoCaps(11)).foregroundStyle(.secondary)
            Text("·").foregroundStyle(.secondary)
            Text("ESC: cancel").font(NeonFont.monoCaps(11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: 420)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(NeonPalette.cyberCyan.opacity(0.7), lineWidth: 1))
        )
        .overlay(neonEdge)
        .modifier(NeonGlow.outer(NeonPalette.cyberCyan, radius: 14, opacity: 0.35))
        .padding(.top, 18)
    }

    private var neonEdge: some View {
        Capsule()
            .stroke(NeonPalette.gradientPrimary, lineWidth: 1)
            .opacity(0.5)
    }

    // MARK: - Crosshair body

    @ViewBuilder private func crosshairBody(size: CGSize) -> some View {
        let p = cursorPoint
        Canvas { context, _ in
            let stroke = GraphicsContext.Shading.color(.primary.opacity(0.65))
            let dashed = GraphicsContext.Shading.color(.primary.opacity(0.40))

            // Crosshair lines
            var vline = Path(); vline.move(to: CGPoint(x: p.x, y: 0));    vline.addLine(to: CGPoint(x: p.x, y: size.height))
            var hline = Path(); hline.move(to: CGPoint(x: 0, y: p.y));    hline.addLine(to: CGPoint(x: size.width, y: p.y))
            context.stroke(vline, with: dashed, style: StrokeStyle(lineWidth: 0.7, dash: [4, 6]))
            context.stroke(hline, with: dashed, style: StrokeStyle(lineWidth: 0.7, dash: [4, 6]))

            // Solid selection
            if let r = currentSelectionRect(size: size) {
                var rect = Path(r)
                context.fill(rect, with: .color(.white.opacity(0.06)))
                context.stroke(rect, with: stroke, style: StrokeStyle(lineWidth: 1.2, dash: []))
                drawHandles(rect: r, context: context)
            }
        }
        .blendMode(.plusLighter)

        // Cursor circle
        Circle()
            .stroke(Color.primary.opacity(0.85), lineWidth: 1)
            .frame(width: 22, height: 22)
            .position(x: p.x, y: p.y)
            .allowsHitTesting(false)
    }

    private func drawHandles(rect: CGRect, context: GraphicsContext) {
        let r: CGFloat = 5
        let handleFill: GraphicsContext.Shading = .color(.primary)
        let corners: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        for c in corners {
            var h = Path()
            h.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.fill(h, with: handleFill)
        }
    }

    // MARK: - Window-highlight body

    @ViewBuilder private func windowBody(size: CGSize) -> some View {
        // For each window, draw a stroked rect path; highlight the hovered one.
        Canvas { context, _ in
            for w in windows {
                let local = convertToOverlay(bounds: w.bounds, size: size)
                var p = Path(local)
                let color: Color = (w.id == hoveredWindow?.id) ? NeonPalette.cyberCyan : Color.primary.opacity(0.30)
                let lineWidth: CGFloat = (w.id == hoveredWindow?.id) ? 2.4 : 1.0
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, dash: [2, 4]))
            }
        }
        .blendMode(.plusLighter)

        if let w = hoveredWindow {
            VStack(alignment: .leading, spacing: 2) {
                Text(w.displayName)
                    .font(NeonFont.monoCaps(11))
                    .foregroundStyle(.white)
                Text("\(Int(w.bounds.width)) × \(Int(w.bounds.height))")
                    .font(NeonFont.monoCaps(10))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NeonPalette.cyberCyan, lineWidth: 1.6))
            )
            .modifier(NeonGlow.outer(NeonPalette.cyberCyan, radius: 16, opacity: 0.6))
            .position(x: cursorPoint.x + 90, y: max(cursorPoint.y + 90, 60))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Selected scrim (inverse)

    @ViewBuilder private func selectionScrim(size: CGSize) -> some View {
        if mode == .crosshair, let r = currentSelectionRect(size: size) {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .blendMode(.difference)
        } else if mode == .window, let h = hoveredWindow {
            let r = convertToOverlay(bounds: h.bounds, size: size)
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .blendMode(.difference)
        }
    }

    // MARK: - Readouts

    @ViewBuilder private func rectReadout(_ r: CGRect) -> some View {
        HStack(spacing: 6) {
            Text("\(Int(r.width)) × \(Int(r.height))")
                .font(NeonFont.monoCaps(10))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(.primary.opacity(0.35), lineWidth: 0.6))
    }

    // MARK: - Gestures & helpers

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if mode == .crosshair {
                    if dragStart == nil {
                        LoggerService.shared.info("[capture.drag] onChanged START loc=\(NSStringFromPoint(value.location))")
                        dragStart = value.startLocation
                    }
                    dragCurrent = value.location
                }
            }
            .onEnded { value in
                LoggerService.shared.info("[capture.drag] onEnded mode=\(mode.rawValue) loc=\(NSStringFromPoint(value.location))")
                if mode == .window {
                    let p = value.location
                    if let w = windows.first(where: { convertToOverlay(bounds: $0.bounds, size: size).contains(p) }) {
                        onWindowCaptured(w.id)
                    }
                } else if mode == .crosshair {
                    let r = currentSelectionRect(size: size)
                    if let r, r.width > 8 && r.height > 8 {
                        onRegionCaptured(convertToScreen(r))
                    }
                    dragStart = nil
                    dragCurrent = nil
                }
            }
    }

    private func currentSelectionRect(size: CGSize) -> CGRect? {
        guard let a = dragStart, let b = dragCurrent else { return nil }
        return CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private func handleAccept(size: CGSize) {
        if mode == .crosshair, let r = currentSelectionRect(size: size), r.width > 8, r.height > 8 {
            onRegionCaptured(convertToScreen(r))
        } else if mode == .window, let h = hoveredWindow {
            onWindowCaptured(h.id)
        }
    }

    // Convert overlay-local CGPoint / CGRect (origin top-left, points down)
    // back to screen-global coordinates used by CGWindowListCreateImage.
    private func convertToScreen(_ rect: CGRect) -> CGRect {
        // The overlay's "local" coordinates are top-left origin per SwiftUI;
        // their absolute position is the window's frame on screen (origin at bottom-left in AppKit).
        // We need to translate SwiftUI's top-left-origin local rect back into AppKit's bottom-left screen coords.
        let originX = screen.frame.origin.x + rect.minX
        let originY = screen.frame.origin.y + (screen.frame.height - rect.maxY)
        return CGRect(x: originX, y: originY, width: rect.width, height: rect.height)
    }

    private func convertToOverlay(bounds: CGRect, size: CGSize) -> CGRect {
        // AppKit screen coords -> SwiftUI overlay local (top-left origin)
        let x = bounds.origin.x - screen.frame.origin.x
        let y = (screen.frame.height) - (bounds.origin.y + bounds.height - screen.frame.origin.y)
        return CGRect(x: x, y: y, width: bounds.width, height: bounds.height)
    }

    private func updateHoveredWindow() {
        guard mode == .window else { return }
        let size = NSScreen.main?.frame.size ?? .zero
        let screenPoint = convertToScreen(CGRect(origin: cursorPoint, size: .zero))
        let windowList = ScreenshotService.shared.enumerateWindows()
        hoveredWindow = windowList.first(where: { $0.isCaptureEligible && $0.bounds.contains(screenPoint.origin) })
        _ = size
    }
}
