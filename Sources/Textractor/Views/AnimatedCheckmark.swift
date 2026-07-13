import SwiftUI

/// Animated green confirmation checkmark: a circle springs in, then the check
/// stroke draws itself. Used to confirm a successful image→OCR capture.
public struct AnimatedCheckmark: View {

    public var size: CGFloat = 56
    public var lineWidth: CGFloat = 4

    public init(size: CGFloat = 56, lineWidth: CGFloat = 4) {
        self.size = size
        self.lineWidth = lineWidth
    }

    @State private var drawProgress: CGFloat = 0
    @State private var scale: CGFloat = 0.6
    @State private var ringOpacity: Double = 0

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(ringOpacity), lineWidth: lineWidth + 1)
                .frame(width: size, height: size)

            Circle()
                .fill(Color.green.opacity(0.16))
                .frame(width: size * 0.86, height: size * 0.86)
                .scaleEffect(scale)

            CheckShape()
                .trim(from: 0, to: drawProgress)
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.5, height: size * 0.5)
                .scaleEffect(scale)
        }
        .frame(width: size, height: size)
        .onAppear(perform: runAnimation)
    }

    private func runAnimation() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            scale = 1.0
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.18)) {
            drawProgress = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.18)) {
            ringOpacity = 1.0
        }
    }

    /// The check glyph, normalized to a unit box so it scales with the frame.
    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let x = rect.minX
            let y = rect.minY
            let w = rect.width
            let h = rect.height
            // Three points forming a check, expressed as fractions of the box.
            path.move(to: CGPoint(x: x + w * 0.22, y: y + h * 0.54))
            path.addLine(to: CGPoint(x: x + w * 0.44, y: y + h * 0.74))
            path.addLine(to: CGPoint(x: x + w * 0.80, y: y + h * 0.28))
            return path
        }
    }
}
