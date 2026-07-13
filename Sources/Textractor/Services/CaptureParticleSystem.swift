import AppKit
import SwiftUI
import QuartzCore
#if canImport(AppKit)
import AppKit
#endif

/// A reusable particle emitter that generates glowing accent particles.
final class CaptureParticleSystem {
    static let shared = CaptureParticleSystem()
    
    /// Emits `count` glowing particles at the supplied `point` (in window coords).
    /// Returns an array of `CALayer`s so you can add them to any layer.
    func createGlowingParticles(
        at point: CGPoint,
        count: Int,
        color: Color = Color.chalk.opacity(0.7) // fallback to chalk
    ) -> [CALayer] {
        // Use the generic chalk color if Color initializer isn't available in this context
        let nsColor = NSColor(red: 0.90, green: 0.92, blue: 0.86, alpha: 1.0) // #E6EADC approximated
        let cgColor = nsColor.cgColor
        var particles: [CALayer] = []
        
        for _ in 0..<count {
            let layer = CAShapeLayer()
            let size: CGFloat = .random(in: 4...12)
            layer.path = NSBezierPath(ovalIn: CGRect(x: -size/2, y: -size/2, width: size, height: size)).cgPath
            layer.fillColor = cgColor
            layer.opacity = Float(.random(in: 0.4...0.9))
            
            // Random drift animation
            let drift = CABasicAnimation(keyPath: "position")
            drift.duration = .random(in: 1.0...3.0)
            drift.repeatCount = .infinity
            drift.autoreverses = true
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            let offset = CGPoint(
                x: CGFloat.random(in: -30...30),
                y: CGFloat.random(in: -30...30)
            )
            drift.fromValue = point
            drift.toValue = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
            layer.add(drift, forKey: "drift")
            
            // Gentle pulse animation
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.duration = .random(in: 0.5...1.5)
            pulse.repeatCount = .infinity
            pulse.autoreverses = true
            pulse.fromValue = 0.2
            pulse.toValue = 0.9
            layer.add(pulse, forKey: "pulse")
            
            particles.append(layer)
        }
        
        return particles
    }
    
    /// Adds the particles to the layer of the supplied `NSView`.
    func emit(
        into view: NSView,
        at point: CGPoint,
        count: Int,
        color: Color = Color.chalk.opacity(0.7)
    ) {
        let particles = createGlowingParticles(at: point, count: count, color: color)
        for particle in particles {
            view.layer?.addSublayer(particle)
        }
    }
}

#if canImport(AppKit)
extension Color {
    static let chalk = Color(red: 0.90, green: 0.92, blue: 0.86) // #E6EADC
}
#endif