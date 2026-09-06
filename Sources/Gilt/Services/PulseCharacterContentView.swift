import AppKit
import CoreGraphics

@MainActor
final class PulseCharacterContentView: NSView {
    weak var performer: PulseCharacterPerformer?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        let screenPoint = window?.convertPoint(toScreen: convert(localPoint, to: nil)) ?? .zero
        guard let primaryScreen = NSScreen.screens.first else { return self }
        let flippedY = primaryScreen.frame.height - screenPoint.y
        let captureRect = CGRect(x: screenPoint.x - 0.5, y: flippedY - 0.5, width: 1, height: 1)
        guard let windowID = window?.windowNumber, windowID > 0 else { return self }

        if let image = CGWindowListCreateImage(
            captureRect,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixel: [UInt8] = [0, 0, 0, 0]
            if let context = CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return pixel[3] > 30 ? self : nil
            }
        }

        let hitRect = bounds.insetBy(dx: bounds.width * 0.2, dy: bounds.height * 0.15)
        return hitRect.contains(localPoint) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        performer?.handleClick()
    }
}
