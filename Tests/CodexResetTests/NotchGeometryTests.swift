import AppKit
import XCTest
@testable import CodexReset

final class NotchGeometryTests: XCTestCase {
    func testRefreshStaysBelowQuotaWhenActivityChangesWidth() {
        for gap: CGFloat in [0, 180] {
            let base = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                menuBarHeight: 38, safeAreaTop: gap == 0 ? 0 : 38,
                notchGap: gap, notchCenterX: gap == 0 ? nil : 720)
            for geometry in [base, base.fittingActivity(nil, hasDisclosure: false)] {
                for hasActivity in [true, false] {
                    let detailLeft = (geometry.envelopeWidth - geometry.expandedWidth) / 2
                    let compactLeft = (geometry.envelopeWidth - geometry.compactWidth(hasActivity: hasActivity)) / 2
                    let quotaOffset = geometry.isCapsule ? geometry.leftWingWidth / 2
                        : geometry.leftWingWidth - 12 - geometry.quotaDiameter / 2
                    XCTAssertEqual(detailLeft + geometry.quotaCenterXInDetails(hasActivity: hasActivity),
                        compactLeft + quotaOffset, accuracy: 0.001)
                    XCTAssertGreaterThanOrEqual(geometry.quotaCenterXInDetails(hasActivity: hasActivity) - 14, 0)
                }
            }
        }
    }

    func testCapsuleKeepsReadablePercentageInsideMenuBar() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for barHeight: CGFloat in [18, 20, 22, 24, 28, 36, 48, 64] {
            let geometry = NotchGeometry(screenFrame: frame, menuBarHeight: barHeight,
                safeAreaTop: 0, notchGap: 0, notchCenterX: nil)
            XCTAssertTrue(geometry.isCapsule)
            XCTAssertGreaterThan(geometry.topInset, 0)
            XCTAssertLessThanOrEqual(geometry.topInset + geometry.compactHeight, barHeight - 1)
            XCTAssertEqual(geometry.compactHeight, barHeight - 2)
            XCTAssertGreaterThanOrEqual(geometry.capsuleQuotaFontSize, 12)
            XCTAssertLessThanOrEqual(geometry.capsuleQuotaFontSize + 4, geometry.compactHeight)
            XCTAssertGreaterThanOrEqual(geometry.compactWidth(hasActivity: false), 100)
            XCTAssertGreaterThanOrEqual(geometry.expandedWidth, geometry.compactWidth(hasActivity: true))
            XCTAssertEqual(geometry.frame.midX, frame.midX)
        }
    }

    func testHiddenMenuBarUsesSystemThickness() {
        let frame = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        for systemHeight: CGFloat in [22, 24, 28] {
            for boundary: CGFloat in [0, 1, 2] {
                let visible = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - boundary)
                XCTAssertEqual(NotchGeometry.menuBarHeight(screenFrame: frame, visibleFrame: visible,
                    systemThickness: systemHeight), systemHeight)
            }
        }
        let geometry = NotchGeometry(screenFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
            menuBarHeight: 24, safeAreaTop: 0, notchGap: 0, notchCenterX: nil)
        XCTAssertEqual(geometry.compactHeight, 22)
        XCTAssertEqual(geometry.topInset, 1)
        XCTAssertEqual(geometry.compactWidth(hasActivity: false), 104)
        XCTAssertEqual(geometry.compactWidth(hasActivity: true), 352)
    }

    func testMenuBarMeasurementUsesTopEdgeRegardlessOfDockAndScreenOrigin() {
        let frame = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        for barHeight: CGFloat in [22, 24, 28, 38] {
            for bottomDock: CGFloat in [0, 80] {
                let visible = CGRect(x: frame.minX, y: frame.minY + bottomDock,
                    width: frame.width, height: frame.height - barHeight - bottomDock)
                XCTAssertEqual(NotchGeometry.menuBarHeight(screenFrame: frame, visibleFrame: visible,
                    systemThickness: 22), barHeight)
            }
        }
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
