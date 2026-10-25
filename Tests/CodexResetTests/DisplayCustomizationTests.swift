import AppKit
import XCTest
@testable import CodexReset

@MainActor
final class DisplayCustomizationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var suites: [String] = []

    override func tearDown() {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        super.tearDown()
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "CodexResetTests." + UUID().uuidString
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func thread(tokens: Int64 = 100, turn: Date? = nil) -> ActiveThread {
        ActiveThread(id: "sample", title: "Example", projectName: "Example project", model: "gpt-6.1-sol",
            effort: "ultra", startedAt: turn, isSubagent: false, tokensUsed: tokens)
    }

    func testPreferencesPersistAndTopAndBottomChoicesRemainIndependent() {
        let defaults = isolatedDefaults()
        let store = DashboardStore(defaults: defaults)
        store.preferences.agentOnly()
        store.preferences.topRows = [[.tokenRate], [.model, .effort]]
        store.preferences.detailRows = [[.weeklyReset], [], []]
        let reopened = DashboardStore(defaults: defaults)
        XCTAssertEqual(reopened.preferences, store.preferences)
        XCTAssertFalse(reopened.preferences.showQuota)
        XCTAssertFalse(reopened.preferences.showConversations)
        XCTAssertEqual(reopened.preferences.topRows, [[.tokenRate], [.model, .effort]])
        XCTAssertEqual(reopened.preferences.detailRows, [[.weeklyReset], [], []])
        XCTAssertEqual(reopened.preferences.exampleRows(for: thread()), [["— tok/s"], ["6.1", "Ultra"]])
    }

    func testCorruptSavedPreferencesFallBackToUsableDefaults() {
        let defaults = isolatedDefaults()
        defaults.set(Data("invalid".utf8), forKey: "displayPreferences")
        XCTAssertEqual(DashboardStore(defaults: defaults).preferences, DashboardPreferences())
    }

    func testResetRemainsNewForThreeOpeningsAcrossRelaunchesAndSameSnapshotDoesNotRearmIt() {
        let defaults = isolatedDefaults()
        let started = now.addingTimeInterval(-5 * 3_600)
        let quota = QuotaWindow(usedPercent: 6, durationMinutes: 10_080, resetsAt: started.addingTimeInterval(7 * 86_400))
        let usage = UsageSnapshot(primary: quota, secondary: nil, availableResets: nil, fetchedAt: now)
        var store = DashboardStore(defaults: defaults)
        store.receiveUsage(usage)
        XCTAssertTrue(store.hasUnseenReset)
        for count in 1...3 {
            store.panelOpened()
            XCTAssertTrue(store.showNewResetInPanel)
            XCTAssertEqual(store.lastResetNotice?.presentations, count)
            XCTAssertFalse(store.hasUnseenReset)
            store = DashboardStore(defaults: defaults)
            store.receiveUsage(usage)
        }
        store.panelOpened()
        XCTAssertFalse(store.showNewResetInPanel)
        XCTAssertEqual(store.lastResetNotice?.date, started)
        XCTAssertEqual(store.lastResetNotice?.elapsed(at: now), "há 5h")
    }

    func testOldResetOnFirstInstallIsHistoricalAndFutureCycleDoesNotCreateAnAlert() {
        let defaults = isolatedDefaults()
        let store = DashboardStore(defaults: defaults)
        let started = now.addingTimeInterval(-3 * 86_400)
        let quota = QuotaWindow(usedPercent: 40, durationMinutes: 10_080, resetsAt: started.addingTimeInterval(7 * 86_400))
        store.receiveUsage(UsageSnapshot(primary: quota, secondary: nil, availableResets: nil, fetchedAt: now))
        XCTAssertFalse(store.hasUnseenReset)
        store.panelOpened()
        XCTAssertFalse(store.showNewResetInPanel)
        XCTAssertEqual(store.lastResetNotice?.elapsed(at: now), "há 3d 0h")
    }

    func testDragMovesReordersAndCopiesFromPaletteWithoutDuplicatingAFieldWithinARegion() {
        var preferences = DashboardPreferences()
        preferences.topRows = [[.conversation, .tokenRate], [.model, .effort]]
        preferences.place(.conversation, in: .top, row: 0,
            movingFrom: LayoutPosition(region: .top, row: 0, index: 0))
        XCTAssertEqual(preferences.topRows[0], [.tokenRate, .conversation])
        preferences.place(.conversation, in: .top, row: 0, before: 0,
            movingFrom: LayoutPosition(region: .top, row: 0, index: 1))
        XCTAssertEqual(preferences.topRows[0], [.conversation, .tokenRate])
        preferences.place(.model, in: .top, row: 0)
        XCTAssertEqual(preferences.topRows, [[.conversation, .tokenRate, .model], [.effort]])
        preferences.place(.tokenRate, in: .details, row: 2)
        XCTAssertTrue(preferences.topRows[0].contains(.tokenRate))
        preferences.place(.effort, in: .details, row: 2, movingFrom: LayoutPosition(region: .top, row: 1, index: 0))
        XCTAssertTrue(preferences.topRows[1].isEmpty)
        XCTAssertEqual(preferences.detailRows[2], [.tokenRate, .effort])
    }

    func testManualSizingCannotCrossCameraOrAvailableMenuBarHeight() {
        var preferences = DashboardPreferences()
        preferences.preferredActivityWidth = 9_000
        preferences.preferredDetailWidth = 9_000
        preferences.preferredCompactHeight = 9_000
        preferences.extraDetailHeight = 9_000
        for gap: CGFloat in [0, 220] {
            let base = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                menuBarHeight: 24, safeAreaTop: gap == 0 ? 0 : 38, notchGap: gap, notchCenterX: gap == 0 ? nil : 720)
            let fitted = base.fittingLayout(rows: [["Example", "~123 tok/s"], ["6.1", "Ultra"]],
                hasDisclosure: false, preferences: preferences)
            XCTAssertLessThanOrEqual(fitted.compactHeight, base.compactHeight)
            XCTAssertLessThanOrEqual(fitted.expandedWidth, 1440 - 24)
            XCTAssertLessThanOrEqual(fitted.detailHeight, preferences.detailHeight + 300)
            if gap > 0 {
                let left = fitted.frame.minX + (fitted.envelopeWidth - fitted.compactWidth(hasActivity: true)) / 2
                XCTAssertEqual(left + fitted.leftWingWidth + gap / 2, 720, accuracy: 0.001)
            }
        }
    }

    func testBlendsKeepCameraAnchoredAndControlsReachableWhenEverythingIsHidden() {
        for gap: CGFloat in [0, 220] {
            let base = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
                menuBarHeight: 38, safeAreaTop: gap == 0 ? 0 : 38, notchGap: gap, notchCenterX: gap == 0 ? nil : 1028)
            for quota in [false, true] {
                for activity in [false, true] {
                    var preferences = DashboardPreferences()
                    preferences.agentOnly()
                    preferences.showQuota = quota
                    preferences.topRows = activity ? [[.tokenRate], [.model, .effort]] : [[], []]
                    preferences.detailRows = [[.extraReset, .weeklyReset], [.model, .effort], [.lastReset]]
                    let displayed = activity ? thread() : nil
                    let fitted = base.fittingActivity(displayed, hasDisclosure: false, preferences: preferences)
                    let width = fitted.compactWidth(hasActivity: activity)
                    XCTAssertGreaterThan(width, 0)
                    XCTAssertEqual(fitted.compactHeight, base.compactHeight)
                    let left = fitted.frame.minX + (fitted.envelopeWidth - width) / 2
                    if gap > 0 { XCTAssertEqual(left + fitted.leftWingWidth + gap / 2, base.centerX, accuracy: 0.001) }
                    let refresh = fitted.toolbarRefreshCenterX(hasActivity: activity)
                    let settings = fitted.expandedWidth - refresh
                    XCTAssertGreaterThanOrEqual(refresh - 14, 0)
                    XCTAssertLessThanOrEqual(settings + 14, fitted.expandedWidth)
                    XCTAssertEqual(fitted.expandedWidth / 2 - refresh, settings - fitted.expandedWidth / 2)
                    XCTAssertGreaterThanOrEqual(fitted.expandedWidth / 2 - refresh, 40)
                    XCTAssertGreaterThan(fitted.listDetailHeight, fitted.detailHeight)
                }
            }
        }
    }
}
