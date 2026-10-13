import CoreGraphics
import Foundation

/// Per-frame motion for the dictation pill.
///
/// The recognizer hands back words in bursts. Showing each burst as it lands
/// makes the line jump a chunk at a time, so `revealed` instead moves at a
/// steady pace that quickens with the backlog and eases off as it catches up,
/// like a fast typist keeping pace with speech. The pill's width follows on a
/// spring, which keeps its speed when the next target arrives.
final class DictationPillMotion {
    /// Points of the line shown so far, measured to the far side of the soft reveal edge.
    private(set) var revealed: CGFloat = 0
    /// The pill's width this frame.
    private(set) var width: CGFloat = DictationCaptionLayout.pillHeight
    /// Where the width is heading this frame.
    private(set) var targetWidth: CGFloat = DictationCaptionLayout.pillHeight

    private var revealSpeed: CGFloat = 0
    private var widthVelocity: CGFloat = 0
    private var lastDate: Date?

    /// Seconds the reveal aims to take to clear what is waiting; shorter once speech has stopped.
    static let catchUpTime: CGFloat = 0.45
    static let hurriedCatchUpTime: CGFloat = 0.18
    static let minimumSpeed: CGFloat = 40

    func advance(
        to date: Date,
        revealTarget: CGFloat,
        hurry: Bool,
        reduceMotion: Bool,
        widthFor: (_ revealed: CGFloat) -> CGFloat
    ) {
        let gap = lastDate.map { date.timeIntervalSince($0) } ?? .infinity
        lastDate = date
        // After a pause (the first frame, or a new session) start settled
        // instead of animating from the last session's values.
        let resume = gap > 0.25
        let dt = resume ? 0 : CGFloat(max(0, gap))

        if reduceMotion || resume || revealTarget < revealed {
            // A correction that shortens the line shows at once; nothing un-writes.
            revealed = revealTarget
            revealSpeed = 0
        } else if revealTarget > revealed {
            let backlog = revealTarget - revealed
            let desired = backlog / (hurry ? Self.hurriedCatchUpTime : Self.catchUpTime)
            revealSpeed += (desired - revealSpeed) * (1 - exp(-dt / 0.15))
            revealed = min(revealTarget, revealed + max(revealSpeed, Self.minimumSpeed) * dt)
        }

        targetWidth = widthFor(revealed)
        if reduceMotion || resume {
            width = targetWidth
            widthVelocity = 0
            return
        }
        // Same model as .spring(response: 0.36, dampingFraction: 0.84).
        let frequency = 2 * CGFloat.pi / 0.36
        let stiffness = frequency * frequency
        let damping = 4 * CGFloat.pi * 0.84 / 0.36
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let step = dt / CGFloat(steps)
        for _ in 0..<steps {
            let acceleration = -stiffness * (width - targetWidth) - damping * widthVelocity
            widthVelocity += acceleration * step
            width += widthVelocity * step
        }
    }
}
