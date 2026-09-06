import UniformTypeIdentifiers
import SwiftUI

struct FolderTabsDropDelegate: DropDelegate {
    let isActive: () -> Bool
    let hasSupportedPayload: (DropInfo) -> Bool
    let updateHover: (CGPoint) -> Void
    let performDropAction: (DropInfo) -> Bool
    let clearHover: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        canHandle(info)
    }

    func dropEntered(info: DropInfo) {
        guard canHandle(info) else { return }
        updateHover(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canHandle(info) else { return nil }
        updateHover(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard canHandle(info) else { return }
        clearHover()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canHandle(info) else { return false }
        return performDropAction(info)
    }

    private func canHandle(_ info: DropInfo) -> Bool {
        shouldHandleFolderTabsDrop(
            internalDragIsActive: isActive(),
            payloadIsSupported: hasSupportedPayload(info)
        )
    }
}
