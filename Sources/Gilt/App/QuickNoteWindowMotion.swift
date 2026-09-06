import AppKit

enum QuickNoteAnimationPhase: Sendable {
    case show
    case hide
}

struct QuickNoteWindowMotion: Sendable {
    let fromFrame: NSRect
    let toFrame: NSRect
    let startAlpha: CGFloat
    let endAlpha: CGFloat
    let duration: TimeInterval
    let timingControlPoints: (Float, Float, Float, Float)

    static func make(
        style: QuickNoteAnimationStyle,
        phase: QuickNoteAnimationPhase,
        anchorFrame: NSRect
    ) -> QuickNoteWindowMotion {
        switch phase {
        case .show: return makeShow(style: style, targetFrame: anchorFrame)
        case .hide: return makeHide(style: style, startFrame: anchorFrame)
        }
    }

    private static func makeShow(style: QuickNoteAnimationStyle, targetFrame: NSRect) -> QuickNoteWindowMotion {
        // Smooth deceleration — ends at rest at the target.
        let decel: (Float, Float, Float, Float) = (0.16, 0.84, 0.24, 1.0)
        // Slight overshoot — used by pop/spring styles.
        let spring: (Float, Float, Float, Float) = (0.22, 1.18, 0.28, 1.0)

        switch style {
        case .slide:
            return QuickNoteWindowMotion(
                fromFrame: offset(targetFrame, dx: 0, dy: -18),
                toFrame: targetFrame,
                startAlpha: 0, endAlpha: 1,
                duration: 0.22, timingControlPoints: decel
            )
        case .fade:
            return QuickNoteWindowMotion(
                fromFrame: targetFrame,
                toFrame: targetFrame,
                startAlpha: 0, endAlpha: 1,
                duration: 0.20, timingControlPoints: decel
            )
        case .pop:
            return QuickNoteWindowMotion(
                fromFrame: scaled(targetFrame, by: 0.88),
                toFrame: targetFrame,
                startAlpha: 0, endAlpha: 1,
                duration: 0.26, timingControlPoints: spring
            )
        case .dropFromTop:
            return QuickNoteWindowMotion(
                fromFrame: offset(targetFrame, dx: 0, dy: 80),
                toFrame: targetFrame,
                startAlpha: 0, endAlpha: 1,
                duration: 0.30, timingControlPoints: decel
            )
        case .riseFromBelow:
            return QuickNoteWindowMotion(
                fromFrame: offset(targetFrame, dx: 0, dy: -80),
                toFrame: targetFrame,
                startAlpha: 0, endAlpha: 1,
                duration: 0.30, timingControlPoints: decel
            )
        case .slideFromLeft:
            return QuickNoteWindowMotion(
                fromFrame: offset(targetFrame, dx: -90, dy: 0),
                toFrame: targetFrame,
                startAlpha: 0, endAlpha: 1,
                duration: 0.28, timingControlPoints: decel
            )
        case .slideFromRight:
            return QuickNoteWindowMotion(
                fromFrame: offset(targetFrame, dx: 90, dy: 0),
                toFrame: targetFrame,
                startAlpha: 0, endAlpha: 1,
                duration: 0.28, timingControlPoints: decel
            )
        case .zoomIn:
            return QuickNoteWindowMotion(
                fromFrame: scaled(targetFrame, by: 1.14),
                toFrame: targetFrame,
                startAlpha: 0, endAlpha: 1,
                duration: 0.24, timingControlPoints: decel
            )
        }
    }

    private static func makeHide(style: QuickNoteAnimationStyle, startFrame: NSRect) -> QuickNoteWindowMotion {
        // Acceleration curve — leaves quickly.
        let accel: (Float, Float, Float, Float) = (0.4, 0.0, 0.22, 1.0)
        let ease: (Float, Float, Float, Float) = (0.32, 0.0, 0.4, 1.0)

        switch style {
        case .slide:
            return QuickNoteWindowMotion(
                fromFrame: startFrame,
                toFrame: offset(startFrame, dx: 0, dy: -14),
                startAlpha: 1, endAlpha: 0,
                duration: 0.18, timingControlPoints: accel
            )
        case .fade:
            return QuickNoteWindowMotion(
                fromFrame: startFrame,
                toFrame: startFrame,
                startAlpha: 1, endAlpha: 0,
                duration: 0.16, timingControlPoints: ease
            )
        case .pop:
            return QuickNoteWindowMotion(
                fromFrame: startFrame,
                toFrame: scaled(startFrame, by: 0.90),
                startAlpha: 1, endAlpha: 0,
                duration: 0.16, timingControlPoints: accel
            )
        case .dropFromTop:
            // Mirror of show: falls back up out the top.
            return QuickNoteWindowMotion(
                fromFrame: startFrame,
                toFrame: offset(startFrame, dx: 0, dy: 70),
                startAlpha: 1, endAlpha: 0,
                duration: 0.22, timingControlPoints: accel
            )
        case .riseFromBelow:
            return QuickNoteWindowMotion(
                fromFrame: startFrame,
                toFrame: offset(startFrame, dx: 0, dy: -70),
                startAlpha: 1, endAlpha: 0,
                duration: 0.22, timingControlPoints: accel
            )
        case .slideFromLeft:
            return QuickNoteWindowMotion(
                fromFrame: startFrame,
                toFrame: offset(startFrame, dx: -90, dy: 0),
                startAlpha: 1, endAlpha: 0,
                duration: 0.22, timingControlPoints: accel
            )
        case .slideFromRight:
            return QuickNoteWindowMotion(
                fromFrame: startFrame,
                toFrame: offset(startFrame, dx: 90, dy: 0),
                startAlpha: 1, endAlpha: 0,
                duration: 0.22, timingControlPoints: accel
            )
        case .zoomIn:
            // Zooms further in while fading — feels like it's flying past camera.
            return QuickNoteWindowMotion(
                fromFrame: startFrame,
                toFrame: scaled(startFrame, by: 1.12),
                startAlpha: 1, endAlpha: 0,
                duration: 0.20, timingControlPoints: accel
            )
        }
    }

    func interpolatedFrame(for progress: Double) -> NSRect {
        let eased = easedProgress(for: progress)
        return NSRect(
            x: fromFrame.origin.x + (toFrame.origin.x - fromFrame.origin.x) * eased,
            y: fromFrame.origin.y + (toFrame.origin.y - fromFrame.origin.y) * eased,
            width: fromFrame.width + (toFrame.width - fromFrame.width) * eased,
            height: fromFrame.height + (toFrame.height - fromFrame.height) * eased
        )
    }

    func interpolatedAlpha(for progress: Double) -> CGFloat {
        let eased = easedProgress(for: progress)
        return startAlpha + ((endAlpha - startAlpha) * eased)
    }

    func easedProgress(for progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return cubicBezier(
            t: clamped,
            p1x: Double(timingControlPoints.0),
            p1y: Double(timingControlPoints.1),
            p2x: Double(timingControlPoints.2),
            p2y: Double(timingControlPoints.3)
        )
    }

    // MARK: - Frame helpers

    private static func offset(_ frame: NSRect, dx: CGFloat, dy: CGFloat) -> NSRect {
        NSRect(x: frame.origin.x + dx, y: frame.origin.y + dy, width: frame.width, height: frame.height)
    }

    /// Returns a frame scaled around its center. Used for pop/zoom styles so
    /// the window appears to grow or shrink from its resting position rather
    /// than from a corner.
    private static func scaled(_ frame: NSRect, by scale: CGFloat) -> NSRect {
        let newWidth = frame.width * scale
        let newHeight = frame.height * scale
        return NSRect(
            x: frame.midX - newWidth / 2,
            y: frame.midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
    }

    // MARK: - Bezier

    private func cubicBezier(t: Double, p1x: Double, p1y: Double, p2x: Double, p2y: Double) -> Double {
        var guess = t
        for _ in 0..<8 {
            let x = bezierComponent(guess, p1: p1x, p2: p2x) - t
            let derivative = bezierDerivative(guess, p1: p1x, p2: p2x)
            guard abs(derivative) > 1e-6 else { break }
            guess -= x / derivative
        }
        return bezierComponent(guess, p1: p1y, p2: p2y)
    }

    private func bezierComponent(_ t: Double, p1: Double, p2: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * p1 + 3 * inverse * t * t * p2 + t * t * t
    }

    private func bezierDerivative(_ t: Double, p1: Double, p2: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * p1 + 6 * inverse * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }
}
