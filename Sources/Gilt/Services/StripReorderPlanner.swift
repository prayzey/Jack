import CoreGraphics
import Foundation

enum StripReorderPlacement: Equatable {
    case before
    case after
}

struct HorizontalReorderTarget: Equatable {
    let targetID: UUID
    let placement: StripReorderPlacement
}

func logicalStripPlacement(
    _ placement: StripReorderPlacement,
    newestOnRight: Bool
) -> StripReorderPlacement {
    guard newestOnRight else { return placement }
    return placement == .before ? .after : .before
}

func stripReorderPlacement(locationX: CGFloat, targetWidth: CGFloat) -> StripReorderPlacement {
    guard targetWidth > 0 else { return .before }
    return locationX > (targetWidth / 2) ? .after : .before
}

func nearestHorizontalTargetID(
    ids: [UUID],
    frames: [UUID: CGRect],
    locationX: CGFloat
) -> UUID? {
    var bestID: UUID?
    var bestDistance = CGFloat.greatestFiniteMagnitude

    for id in ids {
        guard let frame = frames[id] else { continue }
        let distance: CGFloat
        if locationX < frame.minX {
            distance = frame.minX - locationX
        } else if locationX > frame.maxX {
            distance = locationX - frame.maxX
        } else {
            distance = 0
        }

        if distance < bestDistance {
            bestDistance = distance
            bestID = id
        }
    }

    return bestID
}

func horizontalReorderTarget(
    ids: [UUID],
    frames: [UUID: CGRect],
    draggedID: UUID,
    locationX: CGFloat
) -> HorizontalReorderTarget? {
    let candidateIDs = ids.filter { $0 != draggedID }
    guard let targetID = nearestHorizontalTargetID(ids: candidateIDs, frames: frames, locationX: locationX),
          let frame = frames[targetID] else {
        return nil
    }

    let placement: StripReorderPlacement
    if locationX <= frame.minX {
        placement = .before
    } else if locationX >= frame.maxX {
        placement = .after
    } else {
        placement = stripReorderPlacement(locationX: locationX - frame.minX, targetWidth: frame.width)
    }

    return HorizontalReorderTarget(targetID: targetID, placement: placement)
}

func reorderedStripIDs(
    ids: [UUID],
    draggedID: UUID,
    targetID: UUID,
    placement: StripReorderPlacement
) -> [UUID]? {
    reorderedIDs(ids: ids, draggedID: draggedID, targetID: targetID, placement: placement)
}

func reorderedProviderIDs(
    ids: [String],
    draggedID: String,
    targetID: String,
    placement: StripReorderPlacement
) -> [String]? {
    reorderedIDs(ids: ids, draggedID: draggedID, targetID: targetID, placement: placement)
}

private func reorderedIDs<ID: Equatable>(
    ids: [ID],
    draggedID: ID,
    targetID: ID,
    placement: StripReorderPlacement
) -> [ID]? {
    guard draggedID != targetID,
          let draggedIndex = ids.firstIndex(of: draggedID),
          ids.contains(targetID) else {
        return nil
    }

    var reordered = ids
    let movedID = reordered.remove(at: draggedIndex)

    guard let adjustedTargetIndex = reordered.firstIndex(of: targetID) else {
        return nil
    }

    let insertionIndex: Int
    switch placement {
    case .before:
        insertionIndex = adjustedTargetIndex
    case .after:
        insertionIndex = adjustedTargetIndex + 1
    }

    reordered.insert(movedID, at: min(insertionIndex, reordered.endIndex))
    return reordered == ids ? nil : reordered
}

// MARK: - Live (gesture-driven) reorder

/// Index the dragged item would land on if released now. `frames` must be the
/// layout snapshot taken when the drag began: the visible pills shift while
/// the drag is in flight, so re-measured frames would feed back into the
/// answer and make the target index oscillate.
func liveReorderIndex(
    ids: [UUID],
    frames: [UUID: CGRect],
    draggedID: UUID,
    translationX: CGFloat
) -> Int? {
    guard let draggedIndex = ids.firstIndex(of: draggedID),
          let draggedFrame = frames[draggedID] else {
        return nil
    }
    let center = draggedFrame.midX + translationX

    if translationX > 0 {
        let passed = ids[(draggedIndex + 1)...].filter { id in
            guard let frame = frames[id] else { return false }
            return frame.midX < center
        }
        return draggedIndex + passed.count
    }

    let passed = ids[..<draggedIndex].filter { id in
        guard let frame = frames[id] else { return false }
        return frame.midX > center
    }
    return draggedIndex - passed.count
}

/// Horizontal shift every non-dragged pill applies so the strip opens a gap at
/// `targetIndex`. Pills between the dragged slot and the target slide by one
/// dragged-pill width (plus spacing); everything else stays put.
func liveReorderShifts(
    ids: [UUID],
    frames: [UUID: CGRect],
    draggedID: UUID,
    targetIndex: Int,
    spacing: CGFloat
) -> [UUID: CGFloat] {
    guard let draggedIndex = ids.firstIndex(of: draggedID),
          let draggedFrame = frames[draggedID],
          targetIndex != draggedIndex,
          ids.indices.contains(targetIndex) else {
        return [:]
    }
    let slot = draggedFrame.width + spacing
    var shifts: [UUID: CGFloat] = [:]
    if targetIndex > draggedIndex {
        for id in ids[(draggedIndex + 1)...targetIndex] { shifts[id] = -slot }
    } else {
        for id in ids[targetIndex..<draggedIndex] { shifts[id] = slot }
    }
    return shifts
}

/// Translates a live target index into the (target, placement) pair the store's
/// `moveFolder` already understands.
func liveReorderCommit(
    ids: [UUID],
    draggedID: UUID,
    targetIndex: Int
) -> HorizontalReorderTarget? {
    guard let draggedIndex = ids.firstIndex(of: draggedID),
          targetIndex != draggedIndex,
          ids.indices.contains(targetIndex) else {
        return nil
    }
    return HorizontalReorderTarget(
        targetID: ids[targetIndex],
        placement: targetIndex > draggedIndex ? .after : .before
    )
}
