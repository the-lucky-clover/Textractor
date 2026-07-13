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

    let frame: CGRect
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
    /// AR rule-of-thirds 3×3 grid overlay. Toggleable via the **G** key while
    /// the capture overlay is on screen so users can frame the capture region
    /// to thirds before pressing RETURN.
    @State private var showsGrid: Bool = true

    public init(
        frame: CGRect,
        initialMode: CaptureMode = .crosshair,
        onRegionCaptured: @escaping OnRegionCaptured,
        onWindowCaptured: @escaping OnWindowCaptured,
        onCancel: @escaping OnCancel
    ) {
        self.frame = frame
        self.initialMode = initialMode
        self.onRegionCaptured = onRegionCaptured
        self.onWindowCaptured = onWindowCaptured
        self.onCancel = onCancel
        self._mode = State(initialValue: initialMode)
    }

    // MARK: Geometry

    private let padding: CGFloat = 28

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Lighter, more-transparent scrim — keeps the user's screen
                // visible while the crosshair is active. 0.18 darkens just
                // enough to highlight the crosshair without obscuring the
                // content underneath.
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .overlay(selectionScrim(size: size))

                // Mode body
                switch mode {
                case .crosshair:
                    crosshairBody(size: size)
                case .window:
                    windowBody(size: size)
                }

                // AR rule-of-thirds 3x3 grid — overlays across the whole screen
                // when `showsGrid` is on. Toggleable via G key.
                if showsGrid {
                    GridOverlayView(size: size)
                        .allowsHitTesting(false)
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
                    updateHoveredWindow(size: size)
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
            .onKeyPress(characters: CharacterSet(charactersIn: "gG")) { _ in
                showsGrid.toggle()
                LoggerService.shared.info("[capture.key] G pressed, showsGrid=\(showsGrid)")
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
            Image(systemName: "flask.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(BreakingDad.toxicGreen)
            Text("Textractor Capture")
                .font(BreakingDadFont.hudCaps(11))
                .foregroundStyle(.primary)
            Spacer()
            Text(mode == .crosshair ? "Region  •  drag" : "Window  •  click")
                .font(BreakingDadFont.hudCaps(11))
                .foregroundStyle(mode == .crosshair ? BreakingDad.toxicGreen : BreakingDad.toxicGreen)
            Text("·").foregroundStyle(.secondary)
            Text("SPACE: switch").font(BreakingDadFont.hudCaps(11)).foregroundStyle(.secondary)
            Text("·").foregroundStyle(.secondary)
            Text("ESC: cancel").font(BreakingDadFont.hudCaps(11)).foregroundStyle(.secondary)
            Text("·").foregroundStyle(.secondary)
            Text(showsGrid ? "G: grid  on" : "G: grid  off")
                .font(BreakingDadFont.hudCaps(11))
                .foregroundStyle(showsGrid ? BreakingDad.toxicGreen : .secondary)
            Button(action: { onCancel() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel capture")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: 420)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(BreakingDad.toxicGreen.opacity(0.7), lineWidth: 1))
        )
        .overlay(neonEdge)
        .shadow(color: BreakingDad.toxicGreen.opacity(0.35), radius: 14)
        .padding(.top, 18)
    }

private var neonEdge: some View {
    Capsule()
        .stroke(BreakingDad.gradient, lineWidth: 1)
        .opacity(0.5)
}

// MARK: - AR 3x3 Rule-of-Thirds Grid

/// A lightweight, non-interactive 3×3 grid overlay used during capture to
/// help the user frame screens by thirds (photography convention). The grid
/// spans the full size it is given; parent controls `showsGrid` via keyboard.
private struct GridOverlayView: View {
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            let stroke = GraphicsContext.Shading.color(.primary.opacity(0.55))
            let dash: [CGFloat] = [3, 5]

            // Two vertical lines at 1/3 and 2/3 of the width.
            var v1 = Path()
            v1.move(to: CGPoint(x: size.width / 3, y: 0))
            v1.addLine(to: CGPoint(x: size.width / 3, y: size.height))
            context.stroke(v1, with: stroke, style: StrokeStyle(lineWidth: 0.6, dash: dash))

            var v2 = Path()
            v2.move(to: CGPoint(x: (size.width / 3) * 2, y: 0))
            v2.addLine(to: CGPoint(x: (size.width / 3) * 2, y: size.height))
            context.stroke(v2, with: stroke, style: StrokeStyle(lineWidth: 0.6, dash: dash))

            // Two horizontal lines at 1/3 and 2/3 of the height.
            var h1 = Path()
            h1.move(to: CGPoint(x: 0, y: size.height / 3))
            h1.addLine(to: CGPoint(x: size.width, y: size.height / 3))
            context.stroke(h1, with: stroke, style: StrokeStyle(lineWidth: 0.6, dash: dash))

            var h2 = Path()
            h2.move(to: CGPoint(x: 0, y: (size.height / 3) * 2))
            h2.addLine(to: CGPoint(x: size.width, y: (size.height / 3) * 2))
            context.stroke(h2, with: stroke, style: StrokeStyle(lineWidth: 0.6, dash: dash))
        }
        .blendMode(.plusLighter)
    }
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
                let rect = Path(r)
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
        // Faint outlines for every eligible (non-hovered) window.
        Canvas { context, _ in
            for w in windows where w.id != hoveredWindow?.id {
                let local = convertToOverlay(bounds: w.bounds, size: size)
                let p = Path(roundedRect: local, cornerRadius: 5)
                context.stroke(
                    p,
                    with: .color(BreakingDad.chalk.opacity(0.16)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [2, 5])
                )
            }
        }
        .allowsHitTesting(false)

        // The hovered window: a true animated pulsing outer bloom (drawn as a
        // real SwiftUI layer so we get an animatable blurred shadow, not the old
        // concentric Canvas strokes).
        if let w = hoveredWindow {
            let r = convertToOverlay(bounds: w.bounds, size: size)
            WindowGlowHighlight(rect: r, color: BreakingDad.toxicGreen)
                .id(w.id)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                Text(w.displayName)
                    .font(BreakingDadFont.hudCaps(11))
                    .foregroundStyle(.white)
                Text("\(Int(w.bounds.width)) × \(Int(w.bounds.height))")
                    .font(BreakingDadFont.hudCaps(10))
                    .foregroundStyle(BreakingDad.hazmatYellow)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BreakingDad.greenBlack.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(BreakingDad.toxicGreen, lineWidth: 1.6)
                    )
            )
            .shadow(color: BreakingDad.toxicGreen.opacity(0.6), radius: 16)
            .position(x: cursorPoint.x + 90, y: max(cursorPoint.y + 90, 60))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Animated window highlight

    /// A pulsing, blurred outer bloom drawn around the hovered window. Uses real
    /// SwiftUI shadows (animatable) rather than concentric Canvas strokes.
    private struct WindowGlowHighlight: View {
        let rect: CGRect
        let color: Color
        @State private var pulse = false

        var body: some View {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(color, lineWidth: 2.5)
                )
                .frame(width: rect.width, height: rect.height)
                .shadow(color: color.opacity(pulse ? 0.95 : 0.45), radius: pulse ? 28 : 14)
                .shadow(color: color.opacity(pulse ? 0.6 : 0.22), radius: pulse ? 46 : 22)
                .position(x: rect.midX, y: rect.midY)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
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
                .font(BreakingDadFont.hudCaps(10))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(.primary.opacity(0.35), lineWidth: 0.6))
    }

    // MARK: - Gestures & helpers

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
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
                    // Use the same hit-test as hover so the highlighted window
                    // is exactly the one that gets captured.
                    if let w = windowAt(point: value.location, size: size) {
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
    // back to screen-global coordinates consumed by ScreenshotService.
    // Overlay-local space matches the live `NSScreen.frame` of the active
    // display — read it fresh from `NSApp.keyWindow` so a drag that started
    // on the MacBook display still maps correctly after the cursor-follow
    // timer animates the overlay onto an external monitor.
    private func liveFrame() -> CGRect {
        NSApp.keyWindow?.frame ?? frame
    }

    private func convertToScreen(_ rect: CGRect) -> CGRect {
        let f = liveFrame()
        let originX = f.origin.x + rect.minX
        let originY = f.origin.y + (f.height - rect.maxY)
        return CGRect(x: originX, y: originY, width: rect.width, height: rect.height)
    }

    /// Height of the primary display (the screen whose AppKit frame origin is
    /// `.zero`). This is the reference height for converting Quartz top-left
    /// global coordinates (used by `CGWindowList` bounds) into AppKit
    /// bottom-left global coordinates.
    private func primaryDisplayHeight() -> CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first)?.frame.height ?? liveFrame().height
    }

    /// Convert a window's `bounds` (Quartz **top-left** origin global coords, as
    /// returned by `CGWindowListCopyWindowInfo`) into overlay-local coordinates
    /// (SwiftUI **top-left** origin, spanning this overlay window). Multi-display
    /// safe: accounts for the overlay window's own AppKit frame and the primary
    /// display height used by the Quartz→AppKit flip.
    private func convertToOverlay(bounds: CGRect, size: CGSize) -> CGRect {
        let f = liveFrame()                       // overlay window, AppKit bottom-left global
        let primaryH = primaryDisplayHeight()
        // Quartz global x already matches AppKit global x.
        let x = bounds.origin.x - f.origin.x
        // Quartz y (down from primary top) → overlay-local y (down from overlay top).
        // Derivation: appKitTop = primaryH - qy;  overlayLocalY = f.maxY - appKitTop
        //           = f.maxY - (primaryH - qy) = qy + f.maxY - primaryH.
        let y = bounds.origin.y + f.maxY - primaryH
        return CGRect(x: x, y: y, width: bounds.width, height: bounds.height)
    }

    /// The single source of truth for "which window is under this overlay-local
    /// point". Used by BOTH hover-highlight and click-to-capture so they always
    /// agree. Returns the frontmost eligible window containing the point
    /// (`windows` is front-to-back z-order).
    private func windowAt(point: CGPoint, size: CGSize) -> WindowDescriptor? {
        windows.first { convertToOverlay(bounds: $0.bounds, size: size).contains(point) }
    }

    private func updateHoveredWindow(size: CGSize) {
        guard mode == .window else { return }
        hoveredWindow = windowAt(point: cursorPoint, size: size)
    }
}
