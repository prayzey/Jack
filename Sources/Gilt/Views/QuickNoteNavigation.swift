import AppKit
import Carbon.HIToolbox
import Foundation

struct QuickNoteNavigationState: Equatable {
    let canNavigateBackward: Bool
    let canNavigateForward: Bool

    static let unavailable = QuickNoteNavigationState(
        canNavigateBackward: false,
        canNavigateForward: false
    )
}

enum QuickNoteSwipeMotion {
    static let travelDistance: CGFloat = 58
    static let outgoingOpacity = 0.24
    static let incomingOpacity = 0.18
    static let springResponse = 0.22
    static let springDampingFraction = 0.92
    static let cleanupDelay: Duration = .milliseconds(190)
}

func quickNoteNavigationState(currentNoteID: UUID?, quickNotes: [NoteItem]) -> QuickNoteNavigationState {
    guard let currentNoteID,
          let currentIndex = quickNotes.firstIndex(where: { $0.noteID == currentNoteID })
    else {
        return .unavailable
    }

    return QuickNoteNavigationState(
        canNavigateBackward: currentIndex > 0,
        canNavigateForward: true
    )
}

func quickNoteCommandNavigationStep(
    charactersIgnoringModifiers: String?,
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags
) -> Int? {
    let relevantFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
    // Arrow keys on physical keyboards always carry .function and .numericPad,
    // so strip those before requiring Command and *nothing else*. A plain
    // `contains(.command)` check hijacked Cmd+Shift+Arrow (select to line
    // start/end) and every other Command combo into note navigation.
    let significantFlags = relevantFlags.subtracting([.function, .numericPad])
    guard significantFlags == [.command] else { return nil }

    switch Int(keyCode) {
    case kVK_LeftArrow:
        return -1
    case kVK_RightArrow:
        return 1
    default:
        break
    }

    switch charactersIgnoringModifiers {
    case "[":
        return -1
    case "]":
        return 1
    default:
        return nil
    }
}
