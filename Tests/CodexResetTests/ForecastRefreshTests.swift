import XCTest
@testable import CodexReset

@MainActor
final class ForecastRefreshTests: XCTestCase {
    func testFailedInitialQueryCanBeRetriedWithoutRestarting() async throws {
        let store = DashboardStore()
        let loader = ForecastLoader()
        store.refreshForecast { try await loader.fetch() }
        XCTAssertTrue(store.isRefreshingForecast)
        await waitUntil { await loader.calls == 1 }
        await loader.fail()
        await waitUntil { !store.isRefreshingForecast }
        XCTAssertNil(store.forecast)
        XCTAssertNotNil(store.forecastError)

        let expected = sampleForecast()
        store.refreshForecast { try await loader.fetch() }
        await waitUntil { await loader.calls == 2 }
        await loader.succeed(expected)
        await waitUntil { !store.isRefreshingForecast }
        XCTAssertEqual(store.forecast?.latest, expected.latest)
        XCTAssertEqual(store.forecast?.sampleSize, 7)
        XCTAssertNil(store.forecastError)
    }

    func testRepeatedClicksAreIgnoredAndFailedRefreshKeepsExistingDeadlines() async throws {
        let store = DashboardStore()
        let loader = ForecastLoader()
        let expected = sampleForecast()
        store.refreshForecast { try await loader.fetch() }
        await waitUntil { await loader.calls == 1 }
        await loader.succeed(expected)
        await waitUntil { !store.isRefreshingForecast }

        store.refreshForecast { try await loader.fetch() }
        store.refreshForecast { XCTFail("A second query must not start while refreshing"); return expected }
        await waitUntil { await loader.calls == 2 }
        XCTAssertEqual(store.forecast?.estimatedWindow?.endsAt, expected.estimatedWindow?.endsAt)
        await loader.fail()
        await waitUntil { !store.isRefreshingForecast }
        XCTAssertEqual(store.forecast?.estimatedWindow?.startsAt, expected.estimatedWindow?.startsAt)
        XCTAssertEqual(store.forecast?.estimatedWindow?.endsAt, expected.estimatedWindow?.endsAt)
        XCTAssertNotNil(store.forecastError)
    }

    private func sampleForecast() -> ResetForecast {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        return ResetForecast(latest: anchor, probabilityNext7Days: nil,
            estimatedWindow: EstimatedResetWindow(startsAt: anchor.addingTimeInterval(86_400),
                endsAt: anchor.addingTimeInterval(172_800)),
            sampleSize: 7, fetchedAt: anchor, scheduledReset: nil,
            sourceURL: ResetForecastService.sourceURL)
    }

    private func waitUntil(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !(await condition()) {
            guard Date() < deadline else {
                XCTFail("Refresh did not reach the expected state", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private actor ForecastLoader {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<ResetForecast, Error>?

    func fetch() async throws -> ResetForecast {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func fail() {
        continuation?.resume(throwing: ResetForecastError.unavailable(503))
        continuation = nil
    }

    func succeed(_ value: ResetForecast) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
