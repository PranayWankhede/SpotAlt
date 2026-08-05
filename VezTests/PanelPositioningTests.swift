import AppKit
import XCTest
@testable import Vez

final class PanelPositioningTests: XCTestCase {
    func testPositionsPanelAboveCenterLikeSpotlight() {
        let screenFrame = NSRect(x: 100, y: 50, width: 1_440, height: 900)
        let panelSize = NSSize(width: 680, height: 68)

        let result = PanelPositioning.spotlightFrame(
            size: panelSize,
            in: screenFrame
        )

        XCTAssertEqual(result.midX, screenFrame.midX)
        XCTAssertEqual(
            result.midY,
            screenFrame.minY + (screenFrame.height * 0.62)
        )
        XCTAssertGreaterThan(result.midY, screenFrame.midY)
        XCTAssertEqual(result.size, panelSize)
    }

    func testKeepsExpandedResultsPanelInsideVisibleScreen() {
        let screenFrame = NSRect(x: 0, y: 25, width: 1_440, height: 780)
        let panelSize = NSSize(width: 680, height: 620)

        let result = PanelPositioning.spotlightFrame(
            size: panelSize,
            in: screenFrame
        )

        XCTAssertGreaterThanOrEqual(result.minY, screenFrame.minY + 20)
        XCTAssertLessThanOrEqual(result.maxY, screenFrame.maxY - 20)
        XCTAssertEqual(result.midX, screenFrame.midX)
    }
}
