import AppKit
import CoreGraphics

enum DockVisibility {
    static func screenHasVisibleDockReservedArea(
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> Bool {
        visibleFrame.minX > screenFrame.minX
            || visibleFrame.minY > screenFrame.minY
            || visibleFrame.maxX < screenFrame.maxX
    }

    static func estimatedDockRect(for screen: NSScreen) -> CGRect {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
        let slotWidth = tileSize * 1.25

        var persistentApps = dockDefaults?.array(forKey: "persistent-apps")?.count ?? 0
        var persistentOthers = dockDefaults?.array(forKey: "persistent-others")?.count ?? 0
        if persistentApps == 0 && persistentOthers == 0 {
            persistentApps = 5
            persistentOthers = 3
        }

        let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
        let recentApps = showRecents ? (dockDefaults?.array(forKey: "recent-apps")?.count ?? 0) : 0
        let totalIcons = persistentApps + persistentOthers + recentApps

        var dividers = 0
        if persistentApps > 0 && (persistentOthers > 0 || recentApps > 0) { dividers += 1 }
        if persistentOthers > 0 && recentApps > 0 { dividers += 1 }
        if showRecents && recentApps > 0 { dividers += 1 }

        let dividerWidth: CGFloat = 12
        let estimatedWidth = max(
            slotWidth * CGFloat(max(totalIcons, 1)) + CGFloat(dividers) * dividerWidth,
            min(screen.frame.width * 0.28, 360)
        ) * 1.15

        let x = screen.frame.minX + ((screen.frame.width - estimatedWidth) / 2)
        let reservedHeight = max(screen.visibleFrame.minY - screen.frame.minY, tileSize * 0.95)
        return CGRect(x: x, y: screen.frame.minY, width: estimatedWidth, height: reservedHeight)
    }
}
