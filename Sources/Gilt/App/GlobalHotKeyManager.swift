import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog
import QuartzCore

// DANGER ZONE: Carbon HIToolbox hotkey APIs.
// These are C-era APIs with manual memory management (EventHotKeyRef, EventHandlerRef).
// Always unregister before re-registering — leaked refs cause duplicate fire or crashes.
// The event handler callback runs off-MainActor; dispatch back to MainActor immediately.
@MainActor
final class GlobalHotKeyManager {
    enum RegisteredHotKey: UInt32, CaseIterable {
        case toggleWindow = 1
        case quickNote = 2
        case commandPalette = 4

        var label: String {
            switch self {
            case .toggleWindow: return "toggle-window"
            case .quickNote: return "quick-note"
            case .commandPalette: return "command-palette"
            }
        }
    }

    static let shared = GlobalHotKeyManager()

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "HotKey")
    private let perfLogger = Logger(subsystem: AppBrand.logSubsystem, category: "HotKeyPerformance")
    private let debugLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private let performanceLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    private let hotKeySignature = OSType(0x41555243)
    private var nextHotKeyEventID: UInt64 = 1

    private var hotKeyRefs: [RegisteredHotKey: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let eventTap = GlobalHotKeyEventTap()
    private var handlers: [RegisteredHotKey: () -> Void] = [:]
    private(set) var registeredShortcuts: [RegisteredHotKey: GlobalShortcut] = [:]

    private init() {}

    @discardableResult
    func registerQuickNoteHotKey(shortcut: GlobalShortcut) -> Bool {
        register(
            role: .quickNote,
            shortcut: shortcut,
            handler: {
                QuickNoteWindowManager.shared.toggle()
            }
        )
    }

    @discardableResult
    func registerCommandPaletteHotKey(shortcut: GlobalShortcut) -> Bool {
        register(
            role: .commandPalette,
            shortcut: shortcut,
            handler: {
                CommandPaletteWindowManager.shared.toggle()
            }
        )
    }

    @discardableResult
    func registerHotKey(shortcut: GlobalShortcut) -> Bool {
        register(
            role: .toggleWindow,
            shortcut: shortcut,
            handler: {
                AppWindowManager.shared.toggleWindow(source: "hotkey:toggle-window")
            }
        )
    }

    @discardableResult
    private func register(
        role: RegisteredHotKey,
        shortcut: GlobalShortcut,
        handler: @escaping () -> Void
    ) -> Bool {
        let registrationStart = CACurrentMediaTime()
        logDebug("registerHotKey start role=\(role.label) shortcut=\(shortcut.displayString)")
        unregister(role: role)

        if shortcut.requiresEventTapFallback {
            if eventTap.register(roleRawValue: role.rawValue, shortcut: shortcut) {
                handlers[role] = handler
                registeredShortcuts[role] = shortcut
                logDebug("Registered event-tap fallback role=\(role.label) shortcut=\(shortcut.displayString)")
                logPerf("registerHotKey event-tap success duration=\(elapsedMillis(since: registrationStart))ms")
                return true
            }

            handlers.removeValue(forKey: role)
            registeredShortcuts.removeValue(forKey: role)
            logPerf("registerHotKey event-tap failed duration=\(elapsedMillis(since: registrationStart))ms")
            return false
        }

        guard installEventHandlerIfNeeded() else {
            logPerf("registerHotKey handler-install failed duration=\(elapsedMillis(since: registrationStart))ms")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: role.rawValue)
        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        if registerStatus == noErr, let ref {
            hotKeyRefs[role] = ref
            handlers[role] = handler
            registeredShortcuts[role] = shortcut
            logDebug("Registered shortcut role=\(role.label) shortcut=\(shortcut.displayString)")
            logPerf("registerHotKey success duration=\(elapsedMillis(since: registrationStart))ms")
            return true
        } else {
            handlers.removeValue(forKey: role)
            registeredShortcuts.removeValue(forKey: role)
            logDebug("RegisterEventHotKey failed role=\(role.label) status=\(registerStatus)")
            logPerf("registerHotKey conflict duration=\(elapsedMillis(since: registrationStart))ms status=\(registerStatus)")
            return false
        }
    }

    @discardableResult
    private func installEventHandlerIfNeeded() -> Bool {
        guard eventHandlerRef == nil else { return true }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr,
                      hotKeyID.signature == OSType(0x41555243),
                      let role = RegisteredHotKey(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }

                let callbackTimestamp = CACurrentMediaTime()
                DispatchQueue.main.async {
                    Task { @MainActor in
                        GlobalHotKeyManager.shared.handleRegisteredHotKeyPress(role: role, callbackTimestamp: callbackTimestamp)
                    }
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            logDebug("InstallEventHandler failed status=\(status)")
            return false
        }
        return true
    }

    func unregister(role: RegisteredHotKey) {
        eventTap.unregister(roleRawValue: role.rawValue)
        if let hotKeyRef = hotKeyRefs[role] {
            UnregisterEventHotKey(hotKeyRef)
            hotKeyRefs.removeValue(forKey: role)
            logDebug("Unregistered hotkey role=\(role.label)")
        }
        handlers.removeValue(forKey: role)
        registeredShortcuts.removeValue(forKey: role)
    }

    func unregister() {
        let unregisterStart = CACurrentMediaTime()
        for role in RegisteredHotKey.allCases {
            unregister(role: role)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
            logDebug("Removed previous event handler reference")
        }
        logPerf("unregister duration=\(elapsedMillis(since: unregisterStart))ms")
    }

    private func handleRegisteredHotKeyPress(role: RegisteredHotKey, callbackTimestamp: CFTimeInterval) {
        let eventID = nextHotKeyEventID
        nextHotKeyEventID += 1
        let mainDispatchLatency = (CACurrentMediaTime() - callbackTimestamp) * 1000
        let shortcutDescription = registeredShortcuts[role]?.displayString ?? "Not Registered"
        logPerf(
            "event#\(eventID) event->main dispatch latency="
                + "\(String(format: "%.2f", mainDispatchLatency))ms "
                + "role=\(role.label) shortcut=\(shortcutDescription)"
        )
        let toggleStart = CACurrentMediaTime()
        logDebug("event#\(eventID) role=\(role.label) shortcut=\(shortcutDescription)")
        handlers[role]?()
        logPerf("event#\(eventID) handler dispatch duration=\(elapsedMillis(since: toggleStart))ms")
    }

    func handleEventTapHotKeyPress(roleRawValue: UInt32, callbackTimestamp: CFTimeInterval) {
        guard let role = RegisteredHotKey(rawValue: roleRawValue) else { return }
        handleRegisteredHotKeyPress(role: role, callbackTimestamp: callbackTimestamp)
    }

    private func elapsedMillis(since start: CFTimeInterval) -> String {
        String(format: "%.2f", (CACurrentMediaTime() - start) * 1000)
    }

    private func logDebug(_ message: String) {
        guard debugLoggingEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }

    private func logPerf(_ message: String) {
        guard performanceLoggingEnabled else { return }
        perfLogger.debug("\(message, privacy: .public)")
    }
}
