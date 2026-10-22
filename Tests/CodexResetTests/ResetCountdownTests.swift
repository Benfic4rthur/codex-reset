import XCTest
@testable import CodexReset

final class ResetCountdownTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    func testElapsedHoursReduceBothEndsOfWindow() throws {
        let intervals = Array(repeating: 36.0 * 3_600, count: 12)
            + Array(repeating: 96.0 * 3_600, count: 12)
        let window = try XCTUnwrap(ResetForecastService.estimatedWindow(since: anchor, intervals: intervals))
        XCTAssertEqual(window.presentation(at: anchor).headline, "Entre 1d 12h\ne 4d 0h")
        XCTAssertEqual(window.presentation(at: anchor).caption, "Estimativa histórica")
        XCTAssertEqual(window.presentation(at: anchor.addingTimeInterval(2 * 3_600)).headline, "Entre 1d 10h\ne 3d 22h")
        XCTAssertEqual(window.presentation(at: anchor.addingTimeInterval(2 * 3_600 + 60)).headline, "Entre 1d 9h\ne 3d 21h")
        let refreshed = try XCTUnwrap(ResetForecastService.estimatedWindow(since: anchor, intervals: intervals))
        XCTAssertEqual(refreshed.startsAt, window.startsAt)
        XCTAssertEqual(refreshed.endsAt, window.endsAt)
    }

    func testWindowExpiresWithoutMovingForward() {
        let window = EstimatedResetWindow(startsAt: anchor.addingTimeInterval(3_600),
                                         endsAt: anchor.addingTimeInterval(7_200))
        XCTAssertEqual(window.presentation(at: anchor.addingTimeInterval(3_600)).headline, "Dentro da janela")
        XCTAssertEqual(window.presentation(at: anchor.addingTimeInterval(3_600)).caption, "Estimativa: até 1h 00m")
        XCTAssertEqual(window.presentation(at: anchor.addingTimeInterval(7_200)).headline, "Janela encerrada")
        XCTAssertEqual(window.presentation(at: anchor.addingTimeInterval(9_000)).caption, "Aguardando novos dados")
    }

    func testWeeklyCountdownUsesDaysAndHoursUntilLastDay() {
        let deadline = anchor.addingTimeInterval(162 * 3_600)
        XCTAssertEqual(ResetCountdown.remaining(until: deadline, at: anchor), "6d 18h")
        XCTAssertEqual(ResetCountdown.remaining(until: deadline, at: anchor.addingTimeInterval(3_600)), "6d 17h")
        XCTAssertNil(ResetCountdown.remaining(until: deadline, at: deadline))
    }

    func testCountdownChangesUnitsAtOneDayAndKeepsFinalMinutes() {
        let cases: [(TimeInterval, String)] = [
            (48 * 3_600, "2d 0h"), (24 * 3_600 + 59 * 60, "1d 0h"),
            (24 * 3_600, "1d 0h"), (24 * 3_600 - 1, "23h 59m"),
            (18 * 3_600 + 30 * 60, "18h 30m"), (3_600, "1h 00m"),
            (59 * 60, "59m"), (59, "1m"), (1, "1m")
        ]
        for (seconds, expected) in cases {
            XCTAssertEqual(ResetCountdown.remaining(until: anchor.addingTimeInterval(seconds), at: anchor), expected)
        }
        XCTAssertNil(ResetCountdown.remaining(until: anchor.addingTimeInterval(-1), at: anchor))
    }

    func testInsufficientHistoryDoesNotCreateAnEstimate() {
        XCTAssertNil(ResetForecastService.estimatedWindow(since: anchor,
            intervals: Array(repeating: 86_400, count: 5)))
    }

    func testOldResetsNeverInfluenceTheThirtyDayEstimate() throws {
        let recent = (0...12).map { anchor.addingTimeInterval(-Double($0) * 86_400) }
        let old = [31.0, 45, 60, 90].map { anchor.addingTimeInterval(-$0 * 86_400) }
        let future = [anchor.addingTimeInterval(86_400)]
        let intervals = ResetForecastService.recentIntervals(from: old + recent + future, at: anchor)
        XCTAssertEqual(intervals.count, 12)
        XCTAssertTrue(intervals.allSatisfy { $0 == 86_400 })
        let estimate = try XCTUnwrap(ResetForecastService.estimatedWindow(since: anchor, intervals: intervals))
        XCTAssertEqual(estimate.startsAt, anchor.addingTimeInterval(86_400))
        XCTAssertEqual(estimate.endsAt, anchor.addingTimeInterval(86_400))
    }

    func testThirtyDayBoundaryDoesNotIncludeAnOlderEndpoint() {
        let cutoff = anchor.addingTimeInterval(-30 * 86_400)
        let intervals = ResetForecastService.recentIntervals(from: [cutoff.addingTimeInterval(-1), cutoff,
            cutoff.addingTimeInterval(86_400), anchor], at: anchor)
        XCTAssertEqual(intervals, [86_400, 29 * 86_400])
    }

    func testSixIntervalsAllowAnEstimateWithSmallSampleNotice() throws {
        let window = try XCTUnwrap(ResetForecastService.estimatedWindow(since: anchor,
            intervals: Array(repeating: 86_400, count: 6)))
        XCTAssertEqual(window.presentation(at: anchor, isSmallSample: true).caption, "Estimativa · poucos dados")
        let during = EstimatedResetWindow(startsAt: anchor.addingTimeInterval(-3_600),
            endsAt: anchor.addingTimeInterval(7_200))
        XCTAssertEqual(during.presentation(at: anchor, isSmallSample: true).headline, "Dentro da janela\nAté 2h 00m")
        XCTAssertEqual(during.presentation(at: anchor, isSmallSample: true).caption, "Estimativa · poucos dados")
    }
}
