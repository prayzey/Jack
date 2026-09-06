import AVFoundation
import AppKit

@MainActor
final class PulseCharacterPerformer {
    struct WalkProfile {
        let videoDuration: CFTimeInterval
        let accelStart: CFTimeInterval
        let fullSpeedStart: CFTimeInterval
        let decelStart: CFTimeInterval
        let walkStop: CFTimeInterval
        let travelPerCycle: CGFloat
        let yOffset: CGFloat
        let flipXOffset: CGFloat
        let startDelay: TimeInterval

        static let bruce = WalkProfile(
            videoDuration: 10.0,
            accelStart: 3.0,
            fullSpeedStart: 3.75,
            decelStart: 8.0,
            walkStop: 8.5,
            travelPerCycle: 250,
            yOffset: -3,
            flipXOffset: 0,
            startDelay: 0
        )
    }

    let videoName: String
    var onClick: ((PulseCharacterPerformer) -> Void)?

    /// When true, Jack stays parked at the end of his walk instead of being
    /// hidden by `tick()` after `totalVisibleDuration`. Set by
    /// `parkAboveDock(on:)` for the Jack "Always on" presence mode.
    var persistAfterWalk = false
    /// When true, the speech bubble window is never shown for this walk.
    /// Used by `parkAboveDock(on:)` so a parked Jack doesn't carry an empty
    /// bubble around.
    var hideBubbleDuringWalk = false

    private let displayHeight: CGFloat
    private let walkProfile: WalkProfile
    private let totalVisibleDuration: TimeInterval = 20
    private let videoWidth: CGFloat = 1080
    private let videoHeight: CGFloat = 1920
    private var displayWidth: CGFloat { displayHeight * (videoWidth / videoHeight) }

    private var characterWindow: NSWindow?
    private var bubbleWindow: NSWindow?
    private var bubbleLabel: NSTextField?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var animationTimer: Timer?

    // MARK: - Patrol state (used by `parkAboveDock` / `tick()` in patrol mode)
    //
    // Modeled after lil-agents (github.com/ryanstephen/lil-agents): Jack
    // wanders inside the dock area with short walks separated by natural
    // pauses, instead of marching across the screen. Each walk consumes
    // one full 10s video cycle (the video's built-in accel/decel matches
    // a natural footstep cadence). Between walks Jack stands still for
    // 5–12 seconds — long enough to feel ambient, short enough that the
    // user notices motion.
    private var patrolDockOriginX: CGFloat = 0
    private var patrolDockWidth: CGFloat = 0
    private var patrolBaselineY: CGFloat = 0
    /// Position along the dock, normalized to 0…1 (0 = leftmost, 1 = rightmost).
    private var patrolPositionProgress: CGFloat = 0.5
    private var patrolGoingRight = true
    private var patrolIsPaused = true
    private var patrolPauseEndTime: CFTimeInterval = 0
    private var patrolWalkStartTime: CFTimeInterval = 0
    private var patrolWalkStartPos: CGFloat = 0
    private var patrolWalkEndPos: CGFloat = 0
    /// Each walk covers between this fraction of `referenceTravelWidth`.
    /// Values from lil-agents; gives short, natural-looking strolls.
    private let patrolWalkAmountRange: ClosedRange<CGFloat> = 0.25...0.5
    /// Reference width used to convert the fractional walk amount to pixels.
    /// Matches lil-agents so walk speed feels right on any dock size.
    private let patrolReferenceTravelWidth: CGFloat = 500
    private let patrolPauseRange: ClosedRange<Double> = 5.0...12.0

    private var presentationStartedAt: CFTimeInterval = 0
    private var accumulatedPausedDuration: CFTimeInterval = 0
    private var pauseBeganAt: CFTimeInterval?
    private var hasStartedPlayback = false
    private var hasCompletedWalk = false
    private var isPopoverPresented = false

    private var walkStartFrame: CGRect = .zero
    private var walkEndFrame: CGRect = .zero
    private var bubbleSize: CGSize = .zero
    private var currentMessage = ""

    init(videoName: String, displayHeight: CGFloat, walkProfile: WalkProfile) {
        self.videoName = videoName
        self.displayHeight = displayHeight
        self.walkProfile = walkProfile
    }

    var currentFrame: CGRect {
        characterWindow?.frame ?? .zero
    }

    func present(message: String, on screen: NSScreen, laneIndex: Int, accentColor: NSColor) {
        guard ensureCharacterWindow() else { return }
        if !hideBubbleDuringWalk {
            ensureBubbleWindow()
        }
        cancelAnimationTimer()

        currentMessage = message
        let travel = travelFrames(on: screen, laneIndex: laneIndex)
        walkStartFrame = travel.start
        walkEndFrame = travel.end

        presentationStartedAt = CACurrentMediaTime()
        accumulatedPausedDuration = 0
        pauseBeganAt = nil
        hasStartedPlayback = false
        hasCompletedWalk = false
        isPopoverPresented = false

        characterWindow?.setFrame(travel.start, display: false)
        if !hideBubbleDuringWalk {
            updateBubble(message: message, accentColor: accentColor, characterFrame: travel.start, laneIndex: laneIndex)
        }
        showWindows(at: travel.start)
        applyFacingDirection(movingLeft: true)
        queuePlayer?.pause()
        queuePlayer?.seek(to: .zero)
        startAnimationTimer()
    }

    /// Walks Jack onto the screen and *leaves him parked* in patrol mode.
    /// Patrol = the lil-agents loop: short walks within the dock area,
    /// 5–12 seconds of standing-still between each walk, direction chosen
    /// based on current position so Jack doesn't drift off the dock.
    func parkAboveDock(on screen: NSScreen) {
        guard ensureCharacterWindow() else { return }
        persistAfterWalk = true
        hideBubbleDuringWalk = true

        // Capture the dock geometry once at park time. Recomputing on
        // every tick would be cheap but unnecessary — the dock doesn't
        // move during normal use.
        let dockRect = DockVisibility.estimatedDockRect(for: screen)
        patrolDockOriginX = dockRect.minX
        patrolDockWidth = dockRect.width
        let bottomPadding = displayHeight * 0.15
        patrolBaselineY = max(
            screen.frame.minY + 4,
            dockRect.maxY - bottomPadding + walkProfile.yOffset
        )

        // Start at the right edge of the dock so Jack walks ON-screen
        // for his first move (leftward into the dock area).
        patrolPositionProgress = 0.9
        patrolGoingRight = false
        patrolIsPaused = true
        patrolPauseEndTime = CACurrentMediaTime() + 0.8

        // Skip any prior bubble — patrol stays silent.
        bubbleWindow?.orderOut(nil)

        // Position the window and fade in.
        let entryFrame = patrolFrame(at: patrolPositionProgress, goingRight: patrolGoingRight)
        characterWindow?.setFrame(entryFrame, display: false)
        characterWindow?.alphaValue = 0
        characterWindow?.orderFrontRegardless()
        applyFacingDirection(movingLeft: !patrolGoingRight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            characterWindow?.animator().alphaValue = 1
        }

        queuePlayer?.pause()
        queuePlayer?.seek(to: .zero)
        startAnimationTimer()
    }

    /// Reset the parked-state flags so the next `present()` behaves like a
    /// normal walk-and-hide. Called when the user switches presence mode
    /// off or back to `onTriggers`.
    func leaveParkedMode() {
        persistAfterWalk = false
        hideBubbleDuringWalk = false
        patrolIsPaused = true
    }

    // MARK: - Patrol — internal helpers

    /// State machine driven each `tick()` while Jack is parked. Two modes:
    /// either he's paused (waiting for `patrolPauseEndTime`) or he's mid-
    /// walk (interpolating his position via the video's accel/decel curve).
    private func patrolTick() {
        let now = CACurrentMediaTime()

        if patrolIsPaused {
            if now >= patrolPauseEndTime {
                startPatrolWalk()
            }
            // While paused, keep the window pinned at the last position so
            // a screen resolution change still places Jack correctly.
            let frame = patrolFrame(at: patrolPositionProgress, goingRight: patrolGoingRight)
            characterWindow?.setFrameOrigin(frame.origin)
            return
        }

        let elapsed = now - patrolWalkStartTime
        if elapsed >= walkProfile.videoDuration {
            // Reached the end of the walk video — settle at the endpoint
            // and enter the inter-walk pause.
            patrolPositionProgress = patrolWalkEndPos
            enterPatrolPause()
            return
        }

        // Position interpolation uses the same accel/decel curve as the
        // legacy announcement walk, so the visible legs of the video
        // sync with the on-screen sliding. No more freeze-frame jumps.
        let walkNorm = movementPosition(at: elapsed)
        patrolPositionProgress = patrolWalkStartPos
            + (patrolWalkEndPos - patrolWalkStartPos) * walkNorm
        patrolPositionProgress = min(max(patrolPositionProgress, 0), 1)

        let frame = patrolFrame(at: patrolPositionProgress, goingRight: patrolGoingRight)
        characterWindow?.setFrameOrigin(frame.origin)
    }

    /// Begin a new short walk. Direction nudges Jack back toward the
    /// center of the dock when he hits either edge.
    private func startPatrolWalk() {
        patrolIsPaused = false
        patrolWalkStartTime = CACurrentMediaTime()
        patrolWalkStartPos = patrolPositionProgress

        // Position-aware direction: stay inside the dock area.
        if patrolPositionProgress > 0.85 {
            patrolGoingRight = false
        } else if patrolPositionProgress < 0.15 {
            patrolGoingRight = true
        } else {
            patrolGoingRight = Bool.random()
        }

        // Convert the random fraction to a normalized walk distance using
        // the reference travel width — same approach lil-agents uses so
        // speed feels right regardless of the actual dock width.
        let walkPixels = CGFloat.random(in: patrolWalkAmountRange) * patrolReferenceTravelWidth
        let travelDistance = max(patrolDockWidth - displayWidth, 0)
        let walkAmount = travelDistance > 0 ? walkPixels / travelDistance : 0.3

        if patrolGoingRight {
            patrolWalkEndPos = min(patrolWalkStartPos + walkAmount, 1.0)
        } else {
            patrolWalkEndPos = max(patrolWalkStartPos - walkAmount, 0.0)
        }

        applyFacingDirection(movingLeft: !patrolGoingRight)
        queuePlayer?.seek(to: .zero)
        queuePlayer?.play()
    }

    /// End the current walk and queue the next one after a random pause.
    private func enterPatrolPause() {
        patrolIsPaused = true
        queuePlayer?.pause()
        queuePlayer?.seek(to: .zero)
        patrolPauseEndTime = CACurrentMediaTime() + Double.random(in: patrolPauseRange)
    }

    /// Compute the window frame for a given normalized patrol position.
    /// The X anchor depends on the dock origin so Jack tracks dock moves
    /// (resolution change, dock relocation) without code changes.
    private func patrolFrame(at progress: CGFloat, goingRight: Bool) -> CGRect {
        let travelDistance = max(patrolDockWidth - displayWidth, 0)
        let flipComp = goingRight ? 0 : walkProfile.flipXOffset
        let x = patrolDockOriginX + travelDistance * progress + flipComp
        return CGRect(x: x, y: patrolBaselineY, width: displayWidth, height: displayHeight)
    }

    func hideImmediately() {
        cancelAnimationTimer()
        persistAfterWalk = false
        patrolIsPaused = true
        queuePlayer?.pause()
        bubbleWindow?.orderOut(nil)
        characterWindow?.orderOut(nil)
    }

    func setPopoverPresented(_ presented: Bool) {
        guard presented != isPopoverPresented else { return }
        isPopoverPresented = presented

        if presented {
            pauseBeganAt = CACurrentMediaTime()
            queuePlayer?.pause()
            bubbleWindow?.orderOut(nil)
        } else {
            if let pauseBeganAt {
                accumulatedPausedDuration += CACurrentMediaTime() - pauseBeganAt
                self.pauseBeganAt = nil
            }
            if hasStartedPlayback && !hasCompletedWalk {
                queuePlayer?.play()
            }
            if let frame = characterWindow?.frame {
                bubbleWindow?.setFrameOrigin(bubbleOrigin(for: frame))
                bubbleWindow?.orderFrontRegardless()
            }
        }
    }

    func handleClick() {
        onClick?(self)
    }

    private func ensureCharacterWindow() -> Bool {
        if characterWindow != nil { return true }

        guard let videoURL = AppResourceLocator.url(
            forResource: videoName,
            withExtension: "mov",
            subdirectory: "Resources/PulseCharacters"
        ) else {
            return false
        }

        let asset = AVAsset(url: videoURL)
        let player = AVQueuePlayer()
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.clear.cgColor
        layer.frame = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)

        let contentRect = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
        let window = NSWindow(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.moveToActiveSpace, .stationary]
        window.alphaValue = 0

        let contentView = PulseCharacterContentView(frame: contentRect)
        contentView.performer = self
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.addSublayer(layer)
        window.contentView = contentView

        queuePlayer = player
        self.looper = looper
        playerLayer = layer
        characterWindow = window
        return true
    }

    private func ensureBubbleWindow() {
        guard bubbleWindow == nil else { return }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 120, height: 30),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 5)
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.moveToActiveSpace, .stationary]
        window.alphaValue = 0

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.94).cgColor
        container.layer?.cornerRadius = 14
        container.layer?.borderWidth = 1

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.96)
        label.alignment = .center
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        container.addSubview(label)

        window.contentView = container
        bubbleWindow = window
        bubbleLabel = label
    }

    private func startAnimationTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self.tick()
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func cancelAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        guard let characterWindow else { return }

        if isPopoverPresented {
            return
        }

        // Patrol mode runs its own state machine — short walks within the
        // dock area with natural pauses between, never auto-hides.
        if persistAfterWalk {
            patrolTick()
            return
        }

        let activeElapsed = effectiveElapsed
        if activeElapsed >= totalVisibleDuration {
            hideAnimated()
            return
        }

        let movementElapsed = max(0, activeElapsed - walkProfile.startDelay)
        if movementElapsed > 0 && !hasStartedPlayback {
            hasStartedPlayback = true
            queuePlayer?.seek(to: .zero)
            queuePlayer?.play()
        }

        let x = walkXPosition(for: movementElapsed)
        let y = walkStartFrame.minY
        let frame = CGRect(x: x, y: y, width: walkStartFrame.width, height: walkStartFrame.height)
        characterWindow.setFrameOrigin(frame.origin)
        bubbleWindow?.setFrameOrigin(bubbleOrigin(for: frame))

        if x <= walkEndFrame.minX {
            if !hasCompletedWalk {
                hasCompletedWalk = true
                queuePlayer?.pause()
            }
        } else {
            hasCompletedWalk = false
        }

        if !(bubbleWindow?.isVisible ?? false) {
            bubbleWindow?.orderFrontRegardless()
        }
    }

    private var effectiveElapsed: TimeInterval {
        let now = CACurrentMediaTime()
        let paused = pauseBeganAt.map { now - $0 } ?? 0
        return max(0, now - presentationStartedAt - accumulatedPausedDuration - paused)
    }

    private var mirroredXCompensation: CGFloat {
        walkProfile.flipXOffset
    }

    private func walkXPosition(for elapsed: TimeInterval) -> CGFloat {
        guard elapsed > 0 else {
            return walkStartFrame.minX + mirroredXCompensation
        }

        let cycleDuration = walkProfile.videoDuration
        let completedCycles = floor(elapsed / cycleDuration)
        let cycleTime = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        let cycleProgress = movementPosition(at: cycleTime)
        let distanceTravelled = (CGFloat(completedCycles) * walkProfile.travelPerCycle)
            + (cycleProgress * walkProfile.travelPerCycle)
        let unclampedX = walkStartFrame.minX - distanceTravelled
        return max(walkEndFrame.minX, unclampedX) + mirroredXCompensation
    }

    private func movementPosition(at videoTime: CFTimeInterval) -> CGFloat {
        let dIn = walkProfile.fullSpeedStart - walkProfile.accelStart
        let dLin = walkProfile.decelStart - walkProfile.fullSpeedStart
        let dOut = walkProfile.walkStop - walkProfile.decelStart
        let velocity = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)

        if videoTime <= walkProfile.accelStart {
            return 0
        } else if videoTime <= walkProfile.fullSpeedStart {
            let t = videoTime - walkProfile.accelStart
            return CGFloat(velocity * t * t / (2.0 * dIn))
        } else if videoTime <= walkProfile.decelStart {
            let easeInDistance = velocity * dIn / 2.0
            let t = videoTime - walkProfile.fullSpeedStart
            return CGFloat(easeInDistance + velocity * t)
        } else if videoTime <= walkProfile.walkStop {
            let easeInDistance = velocity * dIn / 2.0
            let linearDistance = velocity * dLin
            let t = videoTime - walkProfile.decelStart
            return CGFloat(easeInDistance + linearDistance + velocity * (t - t * t / (2.0 * dOut)))
        } else {
            return 1
        }
    }

    private func updateBubble(message: String, accentColor: NSColor, characterFrame: CGRect, laneIndex: Int) {
        let padding: CGFloat = 16
        let height: CGFloat = 30
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        let bubbleWidth = max(ceil(textSize.width) + padding * 2, 72)
        bubbleSize = CGSize(width: bubbleWidth, height: height)
        let origin = bubbleOrigin(for: characterFrame, laneIndex: laneIndex)

        bubbleWindow?.setFrame(CGRect(origin: origin, size: bubbleSize), display: false)
        if let container = bubbleWindow?.contentView {
            container.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: height)
            container.layer?.borderColor = accentColor.withAlphaComponent(0.65).cgColor
        }
        bubbleLabel?.font = font
        bubbleLabel?.stringValue = message
        bubbleLabel?.frame = NSRect(x: 12, y: 7, width: bubbleWidth - 24, height: 16)
    }

    private func bubbleOrigin(for characterFrame: CGRect, laneIndex: Int = 0) -> CGPoint {
        CGPoint(
            x: characterFrame.midX - bubbleSize.width / 2,
            y: characterFrame.origin.y + characterFrame.height + 18 + CGFloat(laneIndex) * 18
        )
    }

    private func showWindows(at frame: CGRect) {
        guard let characterWindow else { return }

        let liftedOrigin = CGPoint(x: frame.origin.x + 10, y: frame.origin.y - 8)
        characterWindow.setFrameOrigin(liftedOrigin)
        characterWindow.orderFrontRegardless()
        if !hideBubbleDuringWalk {
            bubbleWindow?.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            characterWindow.animator().alphaValue = 1
            characterWindow.animator().setFrameOrigin(frame.origin)
            if !hideBubbleDuringWalk {
                bubbleWindow?.animator().alphaValue = 1
            }
        }
    }

    private func hideAnimated() {
        guard let characterWindow, let bubbleWindow else { return }
        cancelAnimationTimer()
        let queuePlayer = self.queuePlayer

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            characterWindow.animator().alphaValue = 0
            bubbleWindow.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                queuePlayer?.pause()
                characterWindow.orderOut(nil)
                bubbleWindow.orderOut(nil)
            }
        })
    }

    private func applyFacingDirection(movingLeft: Bool) {
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.transform = movingLeft ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        playerLayer.frame = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
        CATransaction.commit()
    }

    private func travelFrames(on screen: NSScreen, laneIndex: Int) -> (start: CGRect, end: CGRect) {
        let dockRect = DockVisibility.estimatedDockRect(for: screen)
        let bottomPadding = displayHeight * 0.15
        let y = max(
            screen.frame.minY + 4,
            dockRect.maxY - bottomPadding + walkProfile.yOffset
        )

        let leadIn = displayWidth * 0.4
        let leadOut = displayWidth * 0.55
        let horizontalLaneOffset = CGFloat(laneIndex) * 170
        let startX = dockRect.maxX + leadIn + horizontalLaneOffset
        let endX = dockRect.minX - leadOut - CGFloat(laneIndex) * 48

        return (
            start: CGRect(x: startX, y: y, width: displayWidth, height: displayHeight),
            end: CGRect(x: endX, y: y, width: displayWidth, height: displayHeight)
        )
    }
}
