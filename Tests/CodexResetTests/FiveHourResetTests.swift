import XCTest
@testable import CodexReset

final class FiveHourResetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSelectsFiveHourWindowInEitherSlotWithoutChangingWeeklyPercentage() {
        let short = QuotaWindow(usedPercent: 80, durationMinutes: 300, resetsAt: now.addingTimeInterval(9_000))
        let week = QuotaWindow(usedPercent: 10, durationMinutes: 10_080, resetsAt: now.addingTimeInterval(86_400))
        for (primary, secondary) in [(short, week), (week, short)] {
            let usage = UsageSnapshot(primary: primary, secondary: secondary, availableResets: nil, fetchedAt: now)
            XCTAssertEqual(usage.fiveHourWindow?.resetsAt, short.resetsAt)
            XCTAssertEqual(usage.weeklyWindow?.resetsAt, week.resetsAt)
            XCTAssertEqual(usage.displayedWindow?.remainingPercent, 90)
        }
        let shortOnly = UsageSnapshot(primary: short, secondary: nil, availableResets: nil, fetchedAt: now)
        XCTAssertNotNil(shortOnly.fiveHourWindow)
        XCTAssertNil(shortOnly.weeklyWindow)
        XCTAssertEqual(shortOnly.displayedWindow?.remainingPercent, 20)
    }

    func testDoesNotGuessUnknownOrOtherDurationsAreFiveHours() {
        for duration: Int? in [nil, 60, 299, 301, 10_080] {
            let window = QuotaWindow(usedPercent: 0, durationMinutes: duration, resetsAt: now.addingTimeInterval(300))
            XCTAssertNil(UsageSnapshot(primary: window, secondary: nil, availableResets: nil, fetchedAt: now).fiveHourWindow)
        }
    }

    @MainActor
    func testCountdownUsesAccountDeadlineAcrossRefreshesAndLanguages() {
        withStore { store in
            let deadline = now.addingTimeInterval(9_000)
            let window = QuotaWindow(usedPercent: 20, durationMinutes: 300, resetsAt: deadline)
            store.receiveUsage(UsageSnapshot(primary: window, secondary: nil, availableResets: nil, fetchedAt: now))
            XCTAssertEqual(store.text(for: .fiveHourReset, at: now), "Em 2h 30m")
            store.receiveUsage(UsageSnapshot(primary: window, secondary: nil, availableResets: nil, fetchedAt: now.addingTimeInterval(600)))
            XCTAssertEqual(store.text(for: .fiveHourReset, at: now.addingTimeInterval(600)), "Em 2h 20m")
            store.preferences.language = .english
            XCTAssertEqual(store.text(for: .fiveHourReset, at: now), "In 2h 30m")
            XCTAssertEqual(store.tr(DashboardField.fiveHourReset.label), "5-hour reset")
            store.preferences.language = .spanish
            XCTAssertEqual(store.text(for: .fiveHourReset, at: now), "En 2h 30m")
            XCTAssertEqual(store.tr(DashboardField.fiveHourReset.label), "Reinicio de 5 horas")
            XCTAssertEqual(store.text(for: .fiveHourReset, at: deadline), store.tr("Aguardando atualização"))
            XCTAssertNil(store.lastResetNotice, "A short window must not be treated as a weekly account reset")
        }
    }

    @MainActor
    func testMissingWindowAndMissingDeadlineDoNotInventCountdowns() {
        withStore { store in
            XCTAssertEqual(store.text(for: .fiveHourReset, at: now), "Aguardando atualização")
            let week = QuotaWindow(usedPercent: 10, durationMinutes: 10_080, resetsAt: now.addingTimeInterval(86_400))
            store.receiveUsage(UsageSnapshot(primary: week, secondary: nil, availableResets: nil, fetchedAt: now))
            XCTAssertEqual(store.text(for: .fiveHourReset, at: now), "Não informado pelo Codex")
            let noDeadline = QuotaWindow(usedPercent: 10, durationMinutes: 300, resetsAt: nil)
            store.receiveUsage(UsageSnapshot(primary: noDeadline, secondary: nil, availableResets: nil, fetchedAt: now))
            XCTAssertEqual(store.text(for: .fiveHourReset, at: now), "Aguardando atualização")
        }
    }

    func testOptionalFieldCanMoveAndPersistWithoutChangingDefaultOrOldLayouts() throws {
        var preferences = DashboardPreferences()
        XCTAssertFalse((preferences.topRows + preferences.detailRows).joined().contains(.fiveHourReset))
        let old = try JSONDecoder().decode(DashboardPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(old, preferences)
        preferences.place(.fiveHourReset, in: .details, row: 1)
        preferences.place(.tiboAnnouncement, in: .details, row: 1)
        XCTAssertEqual(preferences.detailRows[1], [.lastReset, .fiveHourReset, .tiboAnnouncement])
        XCTAssertEqual(DashboardPreferences.detailRowHeight([.fiveHourReset]), DashboardPreferences.detailRowHeight([.weeklyReset]))
        preferences.place(.fiveHourReset, in: .top, row: 0, movingFrom: LayoutPosition(region: .details, row: 1, index: 1))
        let reopened = try JSONDecoder().decode(DashboardPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(reopened.topRows[0], [.project, .fiveHourReset])
        XCTAssertEqual(reopened.detailRows[1], [.lastReset, .tiboAnnouncement])
    }

    @MainActor
    private func withStore(_ body: (DashboardStore) -> Void) {
        let suite = "CodexResetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(DashboardStore(defaults: defaults))
    }
}
