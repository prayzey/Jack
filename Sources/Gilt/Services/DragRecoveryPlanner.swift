import Foundation

enum DragRecoveryAction: Equatable {
    case keepWaiting
    case stopWaiting
    case clearDragState
}

func dragRecoveryAction<DraggedID: Equatable, TargetID>(
    currentDraggedID: DraggedID?,
    expectedDraggedID: DraggedID,
    currentTargetID: TargetID?,
    pressedMouseButtons: Int
) -> DragRecoveryAction {
    guard currentDraggedID == expectedDraggedID else { return .stopWaiting }
    guard currentTargetID == nil else { return .stopWaiting }
    return pressedMouseButtons == 0 ? .clearDragState : .keepWaiting
}
