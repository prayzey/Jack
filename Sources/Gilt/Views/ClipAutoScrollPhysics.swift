import CoreGraphics

struct ClipAutoScrollState: Equatable {
    let direction: Int
    let proximity: CGFloat
}

func clipAutoScrollState(
    frame: CGRect,
    viewportWidth: CGFloat,
    edgeInset: CGFloat = 96
) -> ClipAutoScrollState {
    guard viewportWidth > 0, edgeInset > 0 else {
        return ClipAutoScrollState(direction: 0, proximity: 0)
    }

    let leftProximity = clampUnit((edgeInset - frame.minX) / edgeInset)
    let rightBoundary = viewportWidth - edgeInset
    let rightProximity = clampUnit((frame.maxX - rightBoundary) / edgeInset)

    if leftProximity <= 0, rightProximity <= 0 {
        return ClipAutoScrollState(direction: 0, proximity: 0)
    }

    if leftProximity > rightProximity {
        return ClipAutoScrollState(direction: -1, proximity: leftProximity)
    }

    return ClipAutoScrollState(direction: 1, proximity: rightProximity)
}

func clipAutoScrollSpeed(
    proximity: CGFloat,
    minPointsPerSecond: CGFloat = 220,
    maxPointsPerSecond: CGFloat = 960
) -> CGFloat {
    let clamped = clampUnit(proximity)
    let eased = CGFloat(pow(Double(clamped), 1.35))
    return minPointsPerSecond + (maxPointsPerSecond - minPointsPerSecond) * eased
}

private func clampUnit(_ value: CGFloat) -> CGFloat {
    min(max(value, 0), 1)
}
