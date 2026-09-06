import AppKit
import Foundation
import QuartzCore

struct TrackpadRevealConfiguration: Equatable {
    var bottomEdgeSwipeEnabled = false
    var bottomCenterSwipeEnabled = false

    var isEnabled: Bool {
        bottomEdgeSwipeEnabled || bottomCenterSwipeEnabled
    }
}

// init(settings:) lives in an extension so the struct keeps its synthesized
// memberwise init (declaring any init in the main body would suppress it).
extension TrackpadRevealConfiguration {
    init(settings: AppSettings) {
        self.init(
            bottomEdgeSwipeEnabled: settings.trackpadRevealBottomEdgeSwipeEnabled,
            bottomCenterSwipeEnabled: settings.trackpadRevealBottomCenterSwipeEnabled
        )
    }
}

struct TrackpadRevealSwipeState: Equatable {
    var verticalCarry: CGFloat = 0
    var hasTriggered = false
}

func normalizedFingerDelta(
    _ delta: CGFloat,
    isDirectionInvertedFromDevice: Bool
) -> CGFloat {
    isDirectionInvertedFromDevice ? -delta : delta
}

func trackpadRevealZoneMatches(
    pointerLocation: CGPoint,
    screenFrame: CGRect,
    configuration: TrackpadRevealConfiguration,
    edgeActivationHeight: CGFloat = 84,
    centerActivationWidth: CGFloat = 360
) -> Bool {
    guard configuration.isEnabled, screenFrame.isNull == false, screenFrame.isEmpty == false else {
        return false
    }

    let isNearBottomEdge = pointerLocation.y <= screenFrame.minY + edgeActivationHeight
    guard isNearBottomEdge else { return false }

    if configuration.bottomEdgeSwipeEnabled {
        return true
    }

    guard configuration.bottomCenterSwipeEnabled else { return false }
    let halfWidth = centerActivationWidth / 2
    let centerBand = CGRect(
        x: screenFrame.midX - halfWidth,
        y: screenFrame.minY,
        width: centerActivationWidth,
        height: edgeActivationHeight
    )
    return centerBand.contains(pointerLocation)
}

func advanceTrackpadRevealGesture(
    state: inout TrackpadRevealSwipeState,
    fingerDeltaX: CGFloat,
    fingerDeltaY: CGFloat,
    phase: NSEvent.Phase,
    momentumPhase: NSEvent.Phase,
    pointerLocation: CGPoint,
    screenFrame: CGRect,
    configuration: TrackpadRevealConfiguration,
    swipeThreshold: CGFloat = 42
) -> Bool {
    if phase.contains(.began) || phase.contains(.mayBegin) {
        state = TrackpadRevealSwipeState()
    }

    guard configuration.isEnabled else {
        state = TrackpadRevealSwipeState()
        return false
    }

    guard momentumPhase.isEmpty else {
        if momentumPhase.contains(.ended) {
            state = TrackpadRevealSwipeState()
        }
        return false
    }

    guard trackpadRevealZoneMatches(
        pointerLocation: pointerLocation,
        screenFrame: screenFrame,
        configuration: configuration
    ) else {
        if phase.contains(.ended) || phase.contains(.cancelled) {
            state = TrackpadRevealSwipeState()
        }
        return false
    }

    guard fingerDeltaY > abs(fingerDeltaX), fingerDeltaY > 0.5 else {
        if phase.contains(.ended) || phase.contains(.cancelled) {
            state = TrackpadRevealSwipeState()
        }
        return false
    }

    state.verticalCarry += fingerDeltaY

    guard state.hasTriggered == false, state.verticalCarry >= swipeThreshold else {
        if phase.contains(.ended) || phase.contains(.cancelled) {
            state = TrackpadRevealSwipeState()
        }
        return false
    }

    state.hasTriggered = true
    return true
}

@MainActor
final class TrackpadRevealGestureMonitor {
    static let shared = TrackpadRevealGestureMonitor()

    // AI note:
    // This monitor intentionally stays on supported scroll-wheel events.
    // AppKit global monitors do not expose a reliable finger count, and private
    // multitouch APIs would make this brittle and unsafe to ship.
    private var configuration = TrackpadRevealConfiguration()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var swipeState = TrackpadRevealSwipeState()
    private var lastRevealAt: CFTimeInterval = 0
    private let minimumRevealInterval: CFTimeInterval = 0.45

    private init() {}

    func apply(settings: AppSettings) {
        apply(configuration: TrackpadRevealConfiguration(settings: settings))
    }

    func stop() {
        removeMonitors()
        swipeState = TrackpadRevealSwipeState()
        configuration = TrackpadRevealConfiguration()
    }

    private func apply(configuration: TrackpadRevealConfiguration) {
        guard self.configuration != configuration || globalMonitor == nil || localMonitor == nil else { return }
        self.configuration = configuration
        swipeState = TrackpadRevealSwipeState()

        guard configuration.isEnabled else {
            removeMonitors()
            return
        }

        installMonitorsIfNeeded()
    }

    private func installMonitorsIfNeeded() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleScrollEvent(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            self.handleScrollEvent(event)
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleScrollEvent(_ event: NSEvent) {
        guard configuration.isEnabled else { return }
        guard event.hasPreciseScrollingDeltas else { return }
        guard AppWindowManager.shared.isActiveModeWindowVisible == false else { return }
        guard let screenFrame = activeScreenFrame() else { return }

        let trigger = advanceTrackpadRevealGesture(
            state: &swipeState,
            fingerDeltaX: normalizedFingerDelta(
                event.scrollingDeltaX,
                isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
            ),
            fingerDeltaY: normalizedFingerDelta(
                event.scrollingDeltaY,
                isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
            ),
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            pointerLocation: NSEvent.mouseLocation,
            screenFrame: screenFrame,
            configuration: configuration
        )

        guard trigger else { return }

        let now = CACurrentMediaTime()
        guard now - lastRevealAt >= minimumRevealInterval else { return }
        lastRevealAt = now
        AppWindowManager.shared.toggleWindow(source: "trackpad-reveal")
    }

    private func activeScreenFrame() -> CGRect? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })?.frame
            ?? NSScreen.main?.frame
    }
}
