import SwiftUI
import UniformTypeIdentifiers

struct FolderClipDropDelegate: DropDelegate {
    let targetFolderID: UUID
    let acceptedTypes: [UTType]
    let updateHover: (UUID) -> Void
    let performDropAction: (DropInfo, UUID) -> Bool
    let clearHover: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        updateHover(targetFolderID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return nil }
        updateHover(targetFolderID)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        clearHover()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        return performDropAction(info, targetFolderID)
    }
}
