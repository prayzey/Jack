import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog
import QuartzCore

/// Listens for the user's dictation shortcut and fires push-to-talk or toggle
/// callbacks. Built on a `CGEventTap` because Carbon's `RegisterEventHotKey`
/// can't represent bare modifier keys (Right Option alone, Fn alone, etc.) and
/// doesn't expose left/right-modifier distinctions reliably.
///
/// We listen to `.keyDown`, `.keyUp`, and `.flagsChanged` and:
///   - For push-to-talk on a key combo: fire `onPress` on keyDown, `onRelease` on keyUp.
///   - For push-to-talk on a bare modifier: track `.flagsChanged` for the
///     specific virtual keycode (kVK_RightOption = 61, etc.) and fire on the
///     down → up transition.
///   - For toggle: fire `onToggle` on every fresh down event.
///   - For modifier-double-tap: fire `onToggle` when two presses of the same
///     modifier happen within 350ms.
///
/// **Event consumption (the reason this class is NOT `@MainActor`).**
/// When the bound shortcut is a real key (e.g. `/`), the CGEventTap callback
/// must decide *synchronously, on the C thread*, whether to swallow the event
/// or let it through. Hopping to the main actor first would deliver the
/// keystroke to the focused app before our decision arrived. So instance state
/// touched by the callback is protected by `lock`, and the public API methods
/// also take the lock. Only the user-visible `on*` callbacks bounce to main.
final class DictationHotkeyMonitor: @unchecked Sendable {
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "DictationHotkey")
    private let debugLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"

    /// Closures fired on the main actor when the configured shortcut matches.
    var onPress: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?
    var onToggle: (@MainActor () -> Void)?

    // MARK: - Lock-protected state

    private let lock = NSLock()
    private var _currentShortcut: DictationShortcut = .default
    private var _isActive: Bool = false
    /// True if the configured combo key is currently being held.
    private var _isHolding: Bool = false
    /// Wall clock of last modifier-down for double-tap detection.
    private var _lastModifierDownAt: CFTimeInterval = 0
    /// Keycodes whose `keyDown` we consumed. We MUST consume the matching
    /// `keyUp` too so the focused app doesn't get an unpaired key-up event,
    /// which can leave things like text-field selection in a stuck state.
    private var _suppressedKeyCodes: Set<UInt32> = []

    var currentShortcut: DictationShortcut {
        lock.withLock { _currentShortcut }
    }
    var isActive: Bool {
        lock.withLock { _isActive }
    }

    // MARK: - Tap lifecycle

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// The tap is serviced on its own thread (see `createTap`) so a busy main
    /// thread can never delay keystroke delivery — without this, every key the
    /// user types waits for the main run loop even though this callback was
    /// already written to run lock-protected off the main actor.
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private let doubleTapWindow: CFTimeInterval = 0.35

    /// Install (or update) the tap for the given shortcut. Returns false if
    /// the OS refused the tap, typically because Accessibility permission
    /// isn't granted yet.
    func install(shortcut: DictationShortcut) -> Bool {
        lock.withLock {
            _currentShortcut = shortcut
            _isHolding = false
            _lastModifierDownAt = 0
            _suppressedKeyCodes.removeAll()
        }
        if eventTap == nil {
            guard createTap() else {
                logger.error("Failed to create CGEventTap — Accessibility permission missing?")
                return false
            }
        }
        lock.withLock { _isActive = true }
        logDebug("Installed dictation hotkey: \(shortcut.displayString)")
        return true
    }

    func uninstall() {
        lock.withLock {
            _isActive = false
            _isHolding = false
            _suppressedKeyCodes.removeAll()
        }

        // Disable the tap and stop its dedicated run loop; the tap thread then
        // falls out of CFRunLoopRun() and removes its own source before exiting.
        // CGEvent.tapEnable / CFRunLoopStop are both safe to call cross-thread.
        let (tap, runLoop) = lock.withLock { (eventTap, tapRunLoop) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        lock.withLock {
            eventTap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
        }
    }

    // MARK: - Tap creation

    private func createTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        // The tap is created and serviced on a dedicated thread so its
        // synchronous callback never has to wait behind main-thread work (which
        // would delay every keystroke the user types). Block the caller only
        // until the thread reports whether tap creation succeeded — install
        // happens at launch / settings change, never in a hot path.
        let ready = DispatchSemaphore(value: 0)

        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }

            // .defaultTap (NOT .listenOnly) is required to consume events.
            // Returning `nil` from the callback then makes the event invisible
            // to all downstream apps — that's how we keep the bound key from
            // being typed into the focused text field.
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: Self.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                ready.signal()
                return
            }

            let runLoop = CFRunLoopGetCurrent()
            self.lock.withLock {
                self.eventTap = tap
                self.runLoopSource = source
                self.tapRunLoop = runLoop
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()

            // Park on the dedicated run loop until uninstall() stops it. This
            // thread does nothing else, so the tap callback always runs at once.
            CFRunLoopRun()

            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        thread.name = "com.praisedev.gilt.dictation-hotkey"
        thread.qualityOfService = .userInteractive
        lock.withLock { tapThread = thread }
        thread.start()

        ready.wait()
        return lock.withLock { eventTap != nil }
    }

    // MARK: - C callback (runs on the event tap's thread, not @MainActor)

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<DictationHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

        // Defensive: macOS sometimes disables our tap (slow callback, system
        // hang, etc.) and tells us with one of these synthetic event types.
        // If we don't re-enable, the dictation hotkey silently dies for the
        // rest of the session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                monitor.logger.warning("Event tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            }
            return Unmanaged.passUnretained(event)
        }

        // Snapshot every primitive we need synchronously — CGEvent isn't
        // Sendable, and we can't hand it to the main actor.
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        let shouldConsume = monitor.processEvent(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isAutorepeat: isAutorepeat
        )
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    /// Single decision point: should we eat this event, and (separately) what
    /// callback should fire on the main actor? Runs on the tap's C thread —
    /// every state read/write goes through `lock`.
    private func processEvent(
        type: CGEventType,
        keyCode: UInt32,
        flags: CGEventFlags,
        isAutorepeat: Bool
    ) -> Bool {
        // Snapshot the public state under the lock so we don't fight other
        // threads writing to it.
        let (active, shortcut, holding, lastModDown, alreadySuppressed) = lock.withLock {
            (
                _isActive,
                _currentShortcut,
                _isHolding,
                _lastModifierDownAt,
                _suppressedKeyCodes.contains(keyCode)
            )
        }
        guard active else { return false }

        switch type {
        case .flagsChanged:
            return processFlagsChanged(
                keyCode: keyCode,
                flags: flags,
                shortcut: shortcut,
                holding: holding,
                lastModDown: lastModDown
            )
        case .keyDown:
            return processKeyDown(
                keyCode: keyCode,
                flags: flags,
                isAutorepeat: isAutorepeat,
                shortcut: shortcut,
                holding: holding
            )
        case .keyUp:
            return processKeyUp(
                keyCode: keyCode,
                shortcut: shortcut,
                alreadySuppressed: alreadySuppressed
            )
        default:
            return false
        }
    }

    // MARK: - Bare-modifier path (flagsChanged)

    /// Bare modifiers (Right Option, Fn) don't *type* a character on their
    /// own, so we don't actually need to "consume" their flagsChanged events
    /// to keep them from polluting the focused app. macOS modifier state is
    /// system-tracked anyway; returning `nil` here wouldn't stop other apps
    /// from seeing the modifier. So we just observe and dispatch.
    private func processFlagsChanged(
        keyCode: UInt32,
        flags: CGEventFlags,
        shortcut: DictationShortcut,
        holding: Bool,
        lastModDown: CFTimeInterval
    ) -> Bool {
        guard shortcut.isBareModifier || shortcut.trigger == .modifierDoubleTap else { return false }
        guard keyCode == shortcut.keyCode else { return false }

        let modifierBit = Self.bitMask(forModifierKeyCode: keyCode)
        let isDown = flags.rawValue & modifierBit.rawValue != 0

        switch shortcut.trigger {
        case .pushToTalk:
            if isDown && !holding {
                lock.withLock { _isHolding = true }
                fireOnMain { $0.onPress?() }
            } else if !isDown && holding {
                lock.withLock { _isHolding = false }
                fireOnMain { $0.onRelease?() }
            }
        case .toggle:
            if isDown {
                fireOnMain { $0.onToggle?() }
            }
        case .modifierDoubleTap:
            if isDown {
                let now = CACurrentMediaTime()
                if now - lastModDown <= doubleTapWindow {
                    lock.withLock { _lastModifierDownAt = 0 }
                    fireOnMain { $0.onToggle?() }
                } else {
                    lock.withLock { _lastModifierDownAt = now }
                }
            }
        }
        return false  // never consume modifier state-change events
    }

    // MARK: - Combo key path (keyDown / keyUp)

    private func processKeyDown(
        keyCode: UInt32,
        flags: CGEventFlags,
        isAutorepeat: Bool,
        shortcut: DictationShortcut,
        holding: Bool
    ) -> Bool {
        guard !shortcut.isBareModifier, shortcut.trigger != .modifierDoubleTap else { return false }
        guard keyCode == shortcut.keyCode else { return false }

        let requiredFlags = Self.cgFlags(fromCarbonModifiers: shortcut.modifiers)
        let presentFlags = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        guard presentFlags == requiredFlags else { return false }

        // The keyDown matches. From this point on we MUST return `true` so
        // the focused app doesn't see the character. Even autorepeats get
        // consumed — otherwise holding a toggle key would spam the field.
        lock.withLock { _ = _suppressedKeyCodes.insert(keyCode) }

        // Only fire the user callback on the first edge, not on autorepeats.
        guard !isAutorepeat else { return true }

        switch shortcut.trigger {
        case .pushToTalk:
            if !holding {
                lock.withLock { _isHolding = true }
                fireOnMain { $0.onPress?() }
            }
        case .toggle:
            fireOnMain { $0.onToggle?() }
        case .modifierDoubleTap:
            // Handled in the flagsChanged path; nothing to do here.
            break
        }
        return true
    }

    private func processKeyUp(
        keyCode: UInt32,
        shortcut: DictationShortcut,
        alreadySuppressed: Bool
    ) -> Bool {
        // If we ate the matching keyDown, we MUST eat this keyUp too — even
        // if the binding changed mid-press. Otherwise apps see a phantom
        // key-up they didn't see the key-down for, which breaks some text
        // editors' selection state.
        let didSuppress = lock.withLock {
            _suppressedKeyCodes.remove(keyCode) != nil
        }

        // Only fire the release callback in push-to-talk mode and when this
        // keyUp belongs to the held key.
        if shortcut.trigger == .pushToTalk,
           keyCode == shortcut.keyCode,
           !shortcut.isBareModifier {
            let wasHolding = lock.withLock {
                let was = _isHolding
                if was { _isHolding = false }
                return was
            }
            if wasHolding {
                fireOnMain { $0.onRelease?() }
            }
        }

        return didSuppress || alreadySuppressed
    }

    // MARK: - Main-actor callback dispatch

    /// Calls `body(self)` on the main actor. We capture `self` strongly here
    /// because the closure is invoked once per event and the monitor's
    /// lifetime is the whole app run — no retain-cycle concern.
    private func fireOnMain(_ body: @escaping @Sendable @MainActor (DictationHotkeyMonitor) -> Void) {
        DispatchQueue.main.async { [self] in
            Task { @MainActor in
                body(self)
            }
        }
    }

    // MARK: - Helpers

    /// Returns the `CGEventFlags` bit that toggles for this modifier's keycode
    /// in a `.flagsChanged` event. macOS emits the same generic flag for
    /// either left or right of a modifier pair; we distinguish via keycode.
    private static func bitMask(forModifierKeyCode code: UInt32) -> CGEventFlags {
        switch code {
        case DictationKeyNames.rightOption, DictationKeyNames.leftOption:
            return .maskAlternate
        case DictationKeyNames.rightCommand, DictationKeyNames.leftCommand:
            return .maskCommand
        case DictationKeyNames.rightControl, DictationKeyNames.leftControl:
            return .maskControl
        case DictationKeyNames.rightShift, DictationKeyNames.leftShift:
            return .maskShift
        case DictationKeyNames.capsLock:
            return .maskAlphaShift
        case DictationKeyNames.function:
            return .maskSecondaryFn
        default:
            return []
        }
    }

    private static func cgFlags(fromCarbonModifiers modifiers: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        return flags
    }

    private func logDebug(_ message: String) {
        guard debugLoggingEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }
}
