import AppKit
import XCTest
@testable import CodexReset

final class NotchGeometryTests: XCTestCase {
    func testCapsuleAndRingStayInsideMenuBar() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for barHeight: CGFloat in [18, 20, 22, 24, 28, 36] {
            let geometry = NotchGeometry(screenFrame: frame, menuBarHeight: barHeight,
                safeAreaTop: 0, notchGap: 0, notchCenterX: nil)
            XCTAssertTrue(geometry.isCapsule)
            XCTAssertGreaterThan(geometry.topInset, 0)
            XCTAssertLessThanOrEqual(geometry.topInset + geometry.compactHeight, barHeight - 1)
            XCTAssertLessThanOrEqual(geometry.quotaDiameter + geometry.quotaStrokeWidth, geometry.compactHeight)
            XCTAssertEqual(geometry.frame.midX, frame.midX)
        }
    }

    func testHiddenMenuBarUsesCompactFallback() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
            menuBarHeight: 0, safeAreaTop: 0, notchGap: 0, notchCenterX: nil)
        XCTAssertEqual(geometry.compactHeight, 22)
        XCTAssertEqual(geometry.topInset, 1)
        XCTAssertEqual(geometry.compactWidth(hasActivity: false), 34)
        XCTAssertEqual(geometry.compactWidth(hasActivity: true), 174)
    }

    func testNotchedGeometryRetainsOriginalDimensions() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            menuBarHeight: 38, safeAreaTop: 38, notchGap: 180, notchCenterX: 720)
        XCTAssertFalse(geometry.isCapsule)
        XCTAssertEqual(geometry.topInset, 0)
        XCTAssertEqual(geometry.compactHeight, 36)
        XCTAssertEqual(geometry.leftWingWidth, 48)
        XCTAssertEqual(geometry.expandedWidth, 340)
        XCTAssertEqual(geometry.quotaDiameter, 30)
        XCTAssertEqual(geometry.quotaStrokeWidth, 2.7)
    }
}
