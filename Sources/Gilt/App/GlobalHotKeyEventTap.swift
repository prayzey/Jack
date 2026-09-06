import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog
import QuartzCore

struct GlobalHotKeyEventTapRegistration: Equatable {
    let roleRawValue: UInt32
    let keyCode: UInt32
    let requiredFlags: CGEventFlags

    init(roleRawValue: UInt32, shortcut: GlobalShortcut) {
        self.roleRawValue = roleRawValue
        keyCode = shortcut.keyCode
        requiredFlags = Self.cgFlags(fromCarbonModifiers: shortcut.modifiers)
    }

    func matches(keyCode candidateKeyCode: Int64, flags candidateFlags: CGEventFlags) -> Bool {
        Int64(keyCode) == candidateKeyCode
            && Self.shortcutFlags(from: candidateFlags) == requiredFlags
    }

    static func shortcutFlags(from flags: CGEventFlags) -> CGEventFlags {
        flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
    }

    static func cgFlags(fromCarbonModifiers modifiers: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        return flags
    }
}

// Event-tap fallback for shortcuts macOS Sequoia no longer routes reliably
// through RegisterEventHotKey, especially Option-only and Shift-only combos.
//
// CRITICAL: an active (`.defaultTap`) CGEventTap sits in the *synchronous*
// delivery path of every keystroke — the window server holds the key event
// until the tap's callback returns. The tap callback runs on whatever run loop
// its source is attached to, so attaching it to the main run loop means a busy
// main thread (e.g. SwiftUI re-rendering the clip strip while the user types in
// search) delays delivery of every keystroke to the focused app — felt as typing
// "input delay". The tap therefore runs on a dedicated, always-idle thread so key
// delivery is never gated by main-thread work. All mutable state is guarded by
// `lock`, which is what makes the cross-thread access (`@unchecked Sendable`) safe.
final class GlobalHotKeyEventTap: @unchecked Sendable {
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "HotKey")
    private let debugLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private let lock = NSLock()
    private var registrations: [UInt32: GlobalHotKeyEventTapRegistration] = [:]
    private var suppressedKeyCodes: Set<Int64> = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    @discardableResult
    func register(roleRawValue: UInt32, shortcut: GlobalShortcut) -> Bool {
        lock.withLock {
            registrations[roleRawValue] = GlobalHotKeyEventTapRegistration(
                roleRawValue: roleRawValue,
                shortcut: shortcut
            )
        }

        if installIfNeeded() {
            logDebug("Registered event-tap shortcut role=\(roleRawValue) shortcut=\(shortcut.displayString)")
            return true
        }

        _ = lock.withLock {
            registrations.removeValue(forKey: roleRawValue)
        }
        logDebug("Event tap failed role=\(roleRawValue) shortcut=\(shortcut.displayString)")
        return false
    }

    func unregister(roleRawValue: UInt32) {
        let shouldStop = lock.withLock {
            registrations.removeValue(forKey: roleRawValue)
            return registrations.isEmpty
        }

        if shouldStop {
            stop()
        }
    }

    func stop() {
        lock.withLock {
            registrations.removeAll()
            suppressedKeyCodes.removeAll()
        }

        // Snapshot under the lock, then act outside it. CGEvent.tapEnable and
        // CFRunLoopStop are safe to call cross-thread; stopping the dedicated run
        // loop lets its thread fall out of CFRunLoopRun() and tear itself down.
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

    private func installIfNeeded() -> Bool {
        if lock.withLock({ eventTap != nil }) {
            return true
        }

        // The tap is created and serviced entirely on a dedicated thread so its
        // callback never has to wait behind main-thread work. We block the caller
        // (registration happens at launch/settings-change, not in a hot path) only
        // until the thread reports whether tap creation succeeded.
        let ready = DispatchSemaphore(value: 0)

        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }

            let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: Self.eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                // tapCreate returns nil when Accessibility permission is missing.
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

            // Park this thread on its own run loop, servicing the tap until stop()
            // calls CFRunLoopStop. This thread does nothing else, so the callback
            // always runs immediately — keystrokes are never delayed by SwiftUI.
            CFRunLoopRun()

            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        thread.name = "com.praisedev.gilt.hotkey-eventtap"
        thread.qualityOfService = .userInteractive
        lock.withLock { tapThread = thread }
        thread.start()

        ready.wait()
        // Success is reflected by the thread having published the tap under the lock.
        return lock.withLock { eventTap != nil }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<GlobalHotKeyEventTap>.fromOpaque(refcon).takeUnretainedValue()

        // macOS disables a tap if its callback ever stalls past the system timeout
        // (or after certain input). Re-enable so global shortcuts keep working
        // instead of silently dying for the rest of the session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            monitor.reEnableTap()
            return Unmanaged.passUnretained(event)
        }

        if monitor.shouldConsume(type: type, event: event) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func reEnableTap() {
        lock.withLock {
            guard let eventTap else { return }
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func shouldConsume(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if type == .keyUp {
            return lock.withLock {
                suppressedKeyCodes.remove(keyCode) != nil
            }
        }

        guard type == .keyDown else { return false }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return matchingRegistration(keyCode: keyCode, flags: flags) != nil
        }

        guard let registration = matchingRegistration(keyCode: keyCode, flags: flags) else {
            return false
        }

        _ = lock.withLock {
            suppressedKeyCodes.insert(keyCode)
        }

        let callbackTimestamp = CACurrentMediaTime()
        let roleRawValue = registration.roleRawValue
        DispatchQueue.main.async {
            Task { @MainActor in
                GlobalHotKeyManager.shared.handleEventTapHotKeyPress(
                    roleRawValue: roleRawValue,
                    callbackTimestamp: callbackTimestamp
                )
            }
        }
        return true
    }

    private func matchingRegistration(
        keyCode: Int64,
        flags: CGEventFlags
    ) -> GlobalHotKeyEventTapRegistration? {
        lock.withLock {
            registrations.values.first { registration in
                registration.matches(keyCode: keyCode, flags: flags)
            }
        }
    }

    private func logDebug(_ message: String) {
        guard debugLoggingEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }
}
