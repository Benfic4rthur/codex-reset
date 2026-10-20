import XCTest
@testable import CodexReset

final class ResetCountdownTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    func testElapsedHoursReduceBothEndsOfWindow() throws {
        let intervals = Array(repeating: 36.0 * 3_600, count: 12)
            + Array(repeating: 96.0 * 3_600, count: 12)
        let window = try XCTUnwrap(ResetForecastService.estimatedWindow(since: anchor, intervals: intervals))
        XCTAssertEqual(window.countdown(at: anchor), "36h 00m–96h 00m")
        XCTAssertEqual(window.countdown(at: anchor.addingTimeInterval(2 * 3_600)), "34h 00m–94h 00m")
        XCTAssertEqual(window.countdown(at: anchor.addingTimeInterval(2 * 3_600 + 60)), "33h 59m–93h 59m")
        let refreshed = try XCTUnwrap(ResetForecastService.estimatedWindow(since: anchor, intervals: intervals))
        XCTAssertEqual(refreshed.startsAt, window.startsAt)
        XCTAssertEqual(refreshed.endsAt, window.endsAt)
    }

    func testWindowExpiresWithoutMovingForward() {
        let window = EstimatedResetWindow(startsAt: anchor.addingTimeInterval(3_600),
                                         endsAt: anchor.addingTimeInterval(7_200))
        XCTAssertEqual(window.countdown(at: anchor.addingTimeInterval(3_600)), "Até 1h 00m")
        XCTAssertEqual(window.countdown(at: anchor.addingTimeInterval(7_200)), "Janela encerrada")
        XCTAssertEqual(window.countdown(at: anchor.addingTimeInterval(9_000)), "Janela encerrada")
    }

    func testWeeklyCountdownKeepsMinutePrecisionAcrossDays() {
        let deadline = anchor.addingTimeInterval(73 * 3_600 + 12 * 60)
        XCTAssertEqual(ResetCountdown.remaining(until: deadline, at: anchor), "73h 12m")
        XCTAssertEqual(ResetCountdown.remaining(until: deadline, at: anchor.addingTimeInterval(60)), "73h 11m")
        XCTAssertNil(ResetCountdown.remaining(until: deadline, at: deadline))
    }

    func testInsufficientHistoryDoesNotCreateAnEstimate() {
        XCTAssertNil(ResetForecastService.estimatedWindow(since: anchor,
            intervals: Array(repeating: 86_400, count: 11)))
    }
}
