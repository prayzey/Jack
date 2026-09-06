import SwiftUI

struct StripReorderDropDelegate: DropDelegate {
    let isActive: () -> Bool
    let updateReorder: (CGPoint) -> Void
    let finalizeDrop: (CGPoint) -> Bool
    let clearDropTarget: () -> Void
    let scheduleDragStateRecovery: () -> Void

    func dropEntered(info: DropInfo) {
        guard isActive() else { return }
        updateReorder(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isActive() else { return nil }
        updateReorder(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard isActive() else { return }
        clearDropTarget()
        scheduleDragStateRecovery()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isActive() else { return false }
        return finalizeDrop(info.location)
    }
}
