import AppKit
import XCTest
@testable import CodexReset

final class HoverActivationGeometryTests: XCTestCase {
    func testAllWingsAndTheEntirePhysicalCameraAreaActivateEvenWithReducedBarHeight() {
        for style in QuotaStyle.allCases {
            for showQuota in [true, false] {
                for hasActivity in [true, false] {
                    for height: Double in [20, 36] {
                        var preferences = DashboardPreferences()
                        preferences.quotaStyle = style
                        preferences.showQuota = showQuota
                        preferences.preferredCompactHeight = height
                        let geometry = NotchGeometry(screenFrame: CGRect(x: -2056, y: -100, width: 2056, height: 1329),
                            menuBarHeight: 38, safeAreaTop: 38, notchGap: 220, notchCenterX: -1028)
                            .fittingLayout(rows: hasActivity ? [["Project"], ["6.1 Sol", "Ultra"]] : [],
                                hasDisclosure: hasActivity, preferences: preferences)
                        let width = geometry.compactWidth(hasActivity: hasActivity)
                        let left = geometry.surfaceCenterX - width / 2
                        for x in [left + 1, geometry.centerX, left + width - 1] {
                            for depth: CGFloat in [0, 1, 19, 21, 37.5, 38] {
                                let screenPoint = CGPoint(x: x, y: geometry.screenFrame.maxY - depth)
                                let local = CGPoint(x: screenPoint.x - geometry.frame.minX, y: screenPoint.y - geometry.frame.minY)
                                XCTAssertTrue(geometry.topContains(local, hasActivity: hasActivity), "style=\(style), depth=\(depth), height=\(height)")
                            }
                        }
                        XCTAssertEqual(geometry.compactHeight, height)
                    }
                }
            }
        }
    }

    func testCapsuleIncludesMenuBarEdgeAndSmallSideToleranceWithoutReachingAppContent() {
        for origin in [CGPoint.zero, CGPoint(x: -1920, y: -200)] {
            for barHeight: CGFloat in [18, 22, 28, 38] {
                var preferences = DashboardPreferences()
                preferences.preferredCompactHeight = 12
                let geometry = NotchGeometry(screenFrame: CGRect(origin: origin, size: CGSize(width: 1920, height: 1080)),
                    menuBarHeight: barHeight, safeAreaTop: 0, notchGap: 0, notchCenterX: nil)
                    .fittingLayout(rows: [], hasDisclosure: false, preferences: preferences)
                let left = geometry.surfaceCenterX - geometry.compactWidth(hasActivity: false) / 2
                let right = geometry.surfaceCenterX + geometry.compactWidth(hasActivity: false) / 2
                func contains(_ x: CGFloat, _ depth: CGFloat) -> Bool {
                    geometry.topContains(CGPoint(x: x - geometry.frame.minX,
                        y: geometry.screenFrame.maxY - depth - geometry.frame.minY), hasActivity: false)
                }
                XCTAssertTrue(contains(geometry.centerX, 0))
                XCTAssertTrue(contains(geometry.centerX, barHeight))
                XCTAssertTrue(contains(left - 3, 1))
                XCTAssertTrue(contains(right + 3, barHeight - 1))
                XCTAssertFalse(contains(left - 5, 1))
                XCTAssertFalse(contains(right + 5, 1))
                XCTAssertFalse(contains(geometry.centerX, barHeight + 0.5))
                XCTAssertFalse(contains(geometry.centerX, -0.5))
                XCTAssertLessThanOrEqual(geometry.topInset + geometry.compactHeight, barHeight)
            }
        }
    }

    func testClosedActivationDoesNotSpreadAcrossTheExpandedPanelOrIntoAppWindows() {
        var preferences = DashboardPreferences()
        preferences.preferredDetailWidth = 900
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
            menuBarHeight: 38, safeAreaTop: 38, notchGap: 220, notchCenterX: 1028)
            .fittingLayout(rows: [["Project"]], hasDisclosure: true, preferences: preferences)
        let top = geometry.screenFrame.maxY - geometry.frame.minY
        let farLeftOfDetails = (geometry.envelopeWidth - geometry.expandedWidth) / 2 + 10
        XCTAssertFalse(geometry.topContains(CGPoint(x: farLeftOfDetails, y: top - 10), hasActivity: true))
        XCTAssertTrue(geometry.detailContains(CGPoint(x: farLeftOfDetails, y: top - 50), height: geometry.detailHeight))
        let camera = geometry.centerX - geometry.frame.minX
        XCTAssertFalse(geometry.topContains(CGPoint(x: camera, y: top - 38.5), hasActivity: true))
    }
}

@MainActor
final class HoverActivationStoreTests: XCTestCase {
    private func store() -> DashboardStore {
        let suite = "CodexResetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return DashboardStore(defaults: defaults)
    }

    func testEnteringOpensImmediatelyAndRepeatedPointerSamplesCountOnlyOnePresentation() {
        let store = store()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = QuotaWindow(usedPercent: 10, durationMinutes: 10_080,
            resetsAt: now.addingTimeInterval(7 * 86_400 - 3_600))
        store.receiveUsage(UsageSnapshot(primary: quota, secondary: nil, availableResets: nil, fetchedAt: now))
        store.setHover(true)
        XCTAssertTrue(store.showHoverDetails) // No dispatch delay or wait is allowed for entry.
        XCTAssertEqual(store.lastResetNotice?.presentations, 1)
        store.setHover(true)
        store.setHover(true)
        XCTAssertTrue(store.showHoverDetails)
        XCTAssertEqual(store.lastResetNotice?.presentations, 1)
        store.stop()
    }

    func testLeavingHasGraceAndReturningCancelsTheOldClose() async throws {
        let store = store()
        store.setHover(true)
        store.listExpanded = true
        store.setHover(false)
        XCTAssertTrue(store.showHoverDetails)
        XCTAssertTrue(store.listExpanded)
        store.setHover(true)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(store.showHoverDetails)
        XCTAssertTrue(store.listExpanded)
        store.setHover(false)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(store.showHoverDetails)
        XCTAssertFalse(store.listExpanded)
        store.stop()
    }
}
