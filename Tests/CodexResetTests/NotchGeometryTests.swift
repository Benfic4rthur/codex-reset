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

    func testLargeQuotaFitsAllPercentagesAndHoverInsideTheMeasuredBar() {
        for gap: CGFloat in [0, 180] {
            for barHeight: CGFloat in gap == 0 ? [18, 22, 24, 28, 38, 48, 64] : [28, 32, 38, 48] {
                for manualHeight: Double? in [nil, 20] {
                    var preferences = DashboardPreferences()
                    preferences.quotaStyle = .largeNumber
                    preferences.preferredCompactHeight = manualHeight
                    let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                        menuBarHeight: barHeight, safeAreaTop: gap == 0 ? 0 : barHeight,
                        notchGap: gap, notchCenterX: gap == 0 ? nil : 720)
                        .fittingLayout(rows: [["Example"]], hasDisclosure: true, preferences: preferences)
                    let closed = geometry.quotaNumberMetrics(expanded: false)
                    let opened = geometry.quotaNumberMetrics(expanded: true)
                    XCTAssertGreaterThanOrEqual(opened.fontSize, closed.fontSize)
                    XCTAssertLessThanOrEqual(geometry.topInset + geometry.compactHeight, barHeight)
                    for metrics in [closed, opened] {
                        XCTAssertLessThanOrEqual(metrics.contentHeight, geometry.compactHeight)
                        XCTAssertLessThanOrEqual(metrics.contentWidth, geometry.isCapsule ? geometry.leftWingWidth : geometry.quotaIndicatorWidth)
                        let font = NSFont.monospacedDigitSystemFont(ofSize: metrics.fontSize, weight: .semibold)
                        for percentage in ["0%", "9%", "69%", "99%", "100%", "—%"] {
                            let measured = (percentage as NSString).size(withAttributes: [.font: font])
                            XCTAssertLessThanOrEqual(measured.width, metrics.textWidth)
                            XCTAssertLessThanOrEqual(measured.height, metrics.textHeight)
                        }
                    }
                    if gap > 0 && barHeight == 38 && manualHeight == nil {
                        XCTAssertGreaterThanOrEqual(closed.fontSize, 20)
                        XCTAssertGreaterThan(opened.fontSize, closed.fontSize)
                    }
                }
            }
        }
    }

    func testLargeQuotaCameraAndRefreshStayAnchoredAcrossActivityAndDetailWidths() {
        let base = NotchGeometry(screenFrame: CGRect(x: -2056, y: -100, width: 2056, height: 1329),
            menuBarHeight: 38, safeAreaTop: 38, notchGap: 220, notchCenterX: -1028)
        var previousQuotaX: CGFloat?
        for width: Double in [320, 500, 900] {
            for rows in [[], [["Example project"], ["6.1 Sol", "Ultra"]]] {
                var preferences = DashboardPreferences()
                preferences.quotaStyle = .largeNumber
                preferences.preferredDetailWidth = width
                let geometry = base.fittingLayout(rows: rows, hasDisclosure: !rows.isEmpty, preferences: preferences)
                let left = geometry.frame.minX + (geometry.envelopeWidth - geometry.compactWidth(hasActivity: !rows.isEmpty)) / 2
                XCTAssertEqual(left + geometry.leftWingWidth + geometry.gapWidth / 2, base.centerX, accuracy: 0.001)
                let quotaX = left + geometry.leftWingWidth - 12 - geometry.quotaIndicatorWidth / 2
                if let previousQuotaX { XCTAssertEqual(quotaX, previousQuotaX, accuracy: 0.001) }
                previousQuotaX = quotaX
                let refreshX = geometry.quotaCenterXInDetails(hasActivity: !rows.isEmpty)
                XCTAssertEqual(geometry.frame.minX + (geometry.envelopeWidth - geometry.expandedWidth) / 2 + refreshX,
                    quotaX, accuracy: 0.001)
                XCTAssertLessThanOrEqual(geometry.toolbarRefreshCenterX(hasActivity: true), geometry.expandedWidth / 2 - 40)
            }
        }
    }

    func testCompactRingCanGrowOnHoverWithoutCrossingItsOriginalWingOrBar() {
        for height: Double in [20, 24, 28, 36] {
            var preferences = DashboardPreferences()
            preferences.preferredCompactHeight = height
            let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                menuBarHeight: 38, safeAreaTop: 38, notchGap: 180, notchCenterX: 720)
                .fittingLayout(rows: [], hasDisclosure: false, preferences: preferences)
            let center = geometry.leftWingWidth - 12 - geometry.quotaDiameter / 2
            XCTAssertGreaterThan(geometry.expandedQuotaDiameter, geometry.quotaDiameter)
            XCTAssertLessThanOrEqual(geometry.expandedQuotaDiameter, geometry.compactHeight)
            XCTAssertGreaterThanOrEqual(center - geometry.expandedQuotaDiameter / 2, 0)
            XCTAssertLessThanOrEqual(center + geometry.expandedQuotaDiameter / 2, geometry.leftWingWidth)
        }
    }
}
