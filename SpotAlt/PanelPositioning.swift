import AppKit

enum PanelPositioning {
    /// Positions the launcher like Spotlight: horizontally centered and slightly
    /// above the vertical midpoint so results can grow downward naturally.
    static func spotlightFrame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        let verticalCenter = visibleFrame.minY + (visibleFrame.height * 0.62)
        let preferredY = verticalCenter - (size.height / 2)
        let edgeInset: CGFloat = 20
        let minimumY = visibleFrame.minY + edgeInset
        let maximumY = visibleFrame.maxY - size.height - edgeInset
        let clampedY = maximumY >= minimumY
            ? min(max(preferredY, minimumY), maximumY)
            : visibleFrame.minY

        return NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: clampedY,
            width: size.width,
            height: size.height
        )
    }

    static func activeScreen(from screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? screens.first
    }
}
