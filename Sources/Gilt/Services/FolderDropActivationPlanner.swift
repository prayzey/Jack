import Foundation

func shouldHandleFolderTabsDrop(internalDragIsActive: Bool, payloadIsSupported: Bool) -> Bool {
    internalDragIsActive || payloadIsSupported
}

func folderDropClipID(from payload: String) -> UUID? {
    if let dragItem = StripDragItem(serializedValue: payload),
       case .clip(let id) = dragItem {
        return id
    }

    return UUID(uuidString: payload)
}
