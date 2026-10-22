import XCTest
@testable import CodexReset

@MainActor
final class QuotaResetObservationTests: XCTestCase {
    private let scheduled = Date(timeIntervalSince1970: 1_700_000_000)
    private let week: TimeInterval = 7 * 86_400

    func testReopeningAfterRenewalDismissesExpiredNoticeAndReanchorsSourceIntervals() throws {
        let source = forecast()
        let renewed = scheduled.addingTimeInterval(600)
        let usage = snapshot(used: 1, at: renewed.addingTimeInterval(3_600), started: renewed)
        let observed = try XCTUnwrap(QuotaResetObservation.detectedAt(previous: nil, current: usage, forecast: source))
        XCTAssertEqual(observed, renewed)
        let next = source.reconcilingQuotaReset(at: observed)
        XCTAssertNil(next.scheduledReset)
        XCTAssertEqual(next.latest, renewed)
        XCTAssertEqual(next.estimatedWindow?.startsAt, renewed.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(next.estimatedWindow?.endsAt, renewed.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(next.sampleSize, 6)
        XCTAssertEqual(next.presentation(at: usage.fetchedAt).caption, "Estimativa · poucos dados")
        XCTAssertFalse(next.presentation(at: usage.fetchedAt).headline.contains("anunciado"))

        // The same account timestamps still identify the renewal after spending
        // part of the allowance or reopening the monitor much later.
        let later = snapshot(used: 38, at: renewed.addingTimeInterval(86_400), started: renewed)
        XCTAssertEqual(QuotaResetObservation.detectedAt(previous: nil, current: later, forecast: source), renewed)
    }

    func testFullQuotaAloneDoesNotConfirmAnAnnouncement() {
        let current = snapshot(used: 1, at: scheduled.addingTimeInterval(3_600),
                               started: scheduled.addingTimeInterval(-2 * 86_400))
        XCTAssertNil(QuotaResetObservation.detectedAt(previous: nil, current: current, forecast: forecast()))
        XCTAssertEqual(forecast().reconcilingQuotaReset(at: nil).presentation(at: current.fetchedAt).headline,
                       "Horário anunciado passou")
    }

    func testUnexpectedRefillIsDetectedWithoutAChangedDeadline() {
        let start = scheduled.addingTimeInterval(-2 * 86_400)
        let previous = snapshot(used: 64, at: scheduled, started: start)
        let current = snapshot(used: 2, at: scheduled.addingTimeInterval(30), started: start)
        XCTAssertEqual(QuotaResetObservation.detectedAt(previous: previous, current: current, forecast: forecast()),
                       current.fetchedAt)
    }

    func testNormalWeeklyRolloverAndShortWindowRenewalAreNotExtraResetEvidence() {
        let previous = snapshot(used: 80, at: scheduled.addingTimeInterval(-30), started: scheduled.addingTimeInterval(-week))
        let current = snapshot(used: 0, at: scheduled.addingTimeInterval(30), started: scheduled)
        XCTAssertNil(QuotaResetObservation.detectedAt(previous: previous, current: current, forecast: nil))

        let short = QuotaWindow(usedPercent: 0, durationMinutes: 300, resetsAt: scheduled.addingTimeInterval(3_600))
        let shortOnly = UsageSnapshot(primary: short, secondary: nil, availableResets: nil, fetchedAt: current.fetchedAt)
        XCTAssertNil(QuotaResetObservation.detectedAt(previous: previous, current: shortOnly, forecast: forecast()))
    }

    func testPendingFutureAnnouncementAndOrdinaryConsumptionRemainUnconfirmed() {
        let old = snapshot(used: 1, at: scheduled.addingTimeInterval(-60), started: scheduled.addingTimeInterval(-86_400))
        let current = snapshot(used: 2, at: scheduled.addingTimeInterval(-30), started: scheduled.addingTimeInterval(-86_400))
        XCTAssertNil(QuotaResetObservation.detectedAt(previous: old, current: current, forecast: forecast()))
        let next = forecast().reconcilingQuotaReset(at: scheduled.addingTimeInterval(-86_400))
        XCTAssertNotNil(next.scheduledReset)
        XCTAssertEqual(next.presentation(at: current.fetchedAt).headline, "Em 1m")
    }

    func testNewPublicResetSupersedesStaleAnnouncementAndLocalAnchor() {
        let applied = scheduled.addingTimeInterval(3_600)
        let updated = forecast(latest: applied).reconcilingQuotaReset(at: scheduled.addingTimeInterval(600))
        XCTAssertNil(updated.scheduledReset)
        XCTAssertEqual(updated.latest, applied)
        XCTAssertEqual(updated.estimatedWindow?.startsAt, applied.addingTimeInterval(2 * 86_400))
    }

    func testInsufficientSourceHistoryDoesNotInventNewIntervals() {
        let next = forecast(intervals: [86_400]).reconcilingQuotaReset(at: scheduled.addingTimeInterval(600))
        XCTAssertNil(next.scheduledReset)
        XCTAssertNil(next.estimatedWindow)
        XCTAssertEqual(next.presentation(at: scheduled).caption, "Histórico insuficiente")
    }

    func testStoreKeepsRenewalWhenStaleSourceReturnsAgainAndOnFailure() async throws {
        let loader = RenewalForecastLoader(forecast())
        let store = DashboardStore(forecastLoader: { await loader.fetch() })
        store.refreshForecast()
        await waitUntil { !store.isRefreshingForecast }
        let start = scheduled.addingTimeInterval(-2 * 86_400)
        store.receiveUsage(snapshot(used: 70, at: scheduled, started: start))
        let renewed = scheduled.addingTimeInterval(30)
        store.receiveUsage(snapshot(used: 1, at: renewed, started: start))
        XCTAssertNil(store.forecast?.scheduledReset)
        await waitUntil { !store.isRefreshingForecast }
        let deadline = store.forecast?.estimatedWindow?.endsAt
        XCTAssertEqual(store.forecast?.latest, renewed)
        let afterRefill = await loader.callCount()
        XCTAssertEqual(afterRefill, 2)

        store.receiveUsage(snapshot(used: 1, at: renewed.addingTimeInterval(30), started: start))
        store.refreshForecast()
        await waitUntil { !store.isRefreshingForecast }
        XCTAssertNil(store.forecast?.scheduledReset)
        XCTAssertEqual(store.forecast?.estimatedWindow?.endsAt, deadline)
        let afterRefresh = await loader.callCount()
        XCTAssertEqual(afterRefresh, 3)

        store.refreshForecast { throw ResetForecastError.unavailable(503) }
        await waitUntil { !store.isRefreshingForecast }
        XCTAssertNotNil(store.forecastError)
        XCTAssertNil(store.forecast?.scheduledReset)
        XCTAssertEqual(store.forecast?.estimatedWindow?.endsAt, deadline)
    }

    func testUsageArrivingBeforeSourceIsReconciledWithoutASecondQuery() async {
        let loader = RenewalForecastLoader(forecast())
        let store = DashboardStore(forecastLoader: { await loader.fetch() })
        let renewed = scheduled.addingTimeInterval(600)
        store.receiveUsage(snapshot(used: 1, at: renewed.addingTimeInterval(60), started: renewed))
        store.refreshForecast()
        await waitUntil { !store.isRefreshingForecast }
        XCTAssertNil(store.forecast?.scheduledReset)
        XCTAssertEqual(store.forecast?.latest, renewed)
        let calls = await loader.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testRefillDuringAnExistingQueryIsNotOverwrittenByItsStaleResponse() async {
        let source = forecast()
        let store = DashboardStore(forecastLoader: { source })
        store.refreshForecast()
        await waitUntil { !store.isRefreshingForecast }
        let start = scheduled.addingTimeInterval(-2 * 86_400)
        store.receiveUsage(snapshot(used: 60, at: scheduled, started: start))
        store.refreshForecast {
            try await Task.sleep(nanoseconds: 20_000_000)
            return source
        }
        let renewed = scheduled.addingTimeInterval(30)
        store.receiveUsage(snapshot(used: 1, at: renewed, started: start))
        XCTAssertTrue(store.isRefreshingForecast)
        await waitUntil { !store.isRefreshingForecast }
        XCTAssertNil(store.forecast?.scheduledReset)
        XCTAssertEqual(store.forecast?.latest, renewed)
    }

    func testRefillDoesNotDismissABankedCreditAnnouncement() {
        let source = forecast()
        let banked = ResetForecast(latest: source.latest, probabilityNext7Days: nil,
            estimatedWindow: source.estimatedWindow, sampleSize: source.sampleSize, fetchedAt: source.fetchedAt,
            scheduledReset: ScheduledResetAnnouncement(announcedAt: scheduled.addingTimeInterval(-3_600),
                scheduledFor: scheduled, resetType: "banked", text: "Banked credit",
                sourceURL: URL(string: "https://x.com/thsottiaux/status/456")!),
            sourceURL: source.sourceURL, historicalIntervals: source.historicalIntervals)
        XCTAssertNotNil(banked.reconcilingQuotaReset(at: scheduled.addingTimeInterval(600)).scheduledReset)
    }

    private func forecast(latest: Date? = nil, intervals: [TimeInterval] = Array(repeating: 2 * 86_400, count: 6)) -> ResetForecast {
        let latest = latest ?? scheduled.addingTimeInterval(-2 * 86_400)
        return ResetForecast(latest: latest, probabilityNext7Days: nil,
            estimatedWindow: ResetForecastService.estimatedWindow(since: latest, intervals: intervals),
            sampleSize: intervals.count, fetchedAt: scheduled,
            scheduledReset: ScheduledResetAnnouncement(announcedAt: scheduled.addingTimeInterval(-12 * 3_600),
                scheduledFor: scheduled, resetType: "regular", text: "Reset scheduled",
                sourceURL: URL(string: "https://x.com/thsottiaux/status/123")!),
            sourceURL: ResetForecastService.sourceURL, historicalIntervals: intervals)
    }

    private func snapshot(used: Double, at date: Date, started: Date) -> UsageSnapshot {
        let quota = QuotaWindow(usedPercent: used, durationMinutes: 7 * 24 * 60, resetsAt: started.addingTimeInterval(week))
        return UsageSnapshot(primary: nil, secondary: quota, availableResets: nil, fetchedAt: date)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            guard Date() < deadline else { XCTFail("State did not settle", file: file, line: line); return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private actor RenewalForecastLoader {
    private let value: ResetForecast
    private var calls = 0
    init(_ value: ResetForecast) { self.value = value }
    func fetch() -> ResetForecast { calls += 1; return value }
    func callCount() -> Int { calls }
}
