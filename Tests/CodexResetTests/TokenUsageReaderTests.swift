import XCTest
@testable import CodexReset

final class TokenUsageReaderTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(output: Int, input: Int = 0, cached: Int = 0, after seconds: TimeInterval) throws -> Data {
        let timestamp = ISO8601DateFormatter().string(from: anchor.addingTimeInterval(seconds))
        return try JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": timestamp,
            "payload": ["type": "token_count", "info": ["total_token_usage": ["output_tokens": output,
                "input_tokens": input, "cached_input_tokens": cached, "total_tokens": input + output]]]]) + Data([0x0A])
    }

    func testUsesMetadataSamplesAndDoesNotZeroRateBetweenUpdates() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/token-tests-" + UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = sessions.appendingPathComponent("example.jsonl")
        try (record(output: 100, after: 0) + record(output: 300, after: 10)).write(to: url)
        let reader = TokenUsageReader()
        var thread = ActiveThread(id: "sample", title: "Example", projectName: "Example", model: "test", effort: "high",
            startedAt: anchor, isSubagent: false, rolloutURL: url, turnID: "turn-one")
        let first = try XCTUnwrap(reader.read([thread], root: root, at: anchor.addingTimeInterval(12)).first)
        XCTAssertEqual(first.tokenRate, 20)
        XCTAssertEqual(first.tokenRateSampledAt, anchor.addingTimeInterval(10))
        XCTAssertEqual(reader.read([thread], root: root, at: anchor.addingTimeInterval(17)).first?.tokenRate, 20)
        XCTAssertNil(reader.read([thread], root: root, at: anchor.addingTimeInterval(400)).first?.tokenRate)
        thread.turnID = "turn-two"
        thread = ActiveThread(id: thread.id, title: thread.title, projectName: thread.projectName, model: thread.model,
            effort: thread.effort, startedAt: anchor.addingTimeInterval(20), isSubagent: false, rolloutURL: url, turnID: "turn-two")
        XCTAssertNil(reader.read([thread], root: root, at: anchor.addingTimeInterval(22)).first?.tokenRate)
    }

    func testPartialWritesMessagesAndOutsidePathsCannotBecomeTokenSamples() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/token-tests-" + UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = sessions.appendingPathComponent("example.jsonl")
        try record(output: 100, after: 0).write(to: url)
        let next = try record(output: 200, after: 5)
        let partial = next.prefix(next.count / 2)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: partial)
        let reader = TokenUsageReader()
        let thread = ActiveThread(id: "sample", title: "Example", projectName: "Example", model: "test", effort: "high",
            startedAt: anchor, isSubagent: false, rolloutURL: url, turnID: "one")
        XCTAssertNil(reader.read([thread], root: root, at: anchor.addingTimeInterval(8)).first?.tokenRate)
        try handle.write(contentsOf: next.suffix(from: partial.count))
        let message = try JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": "2027-01-15T08:00:06Z",
            "payload": ["type": "user_message", "message": "token_count is not a measurement"]]) + Data([0x0A])
        try handle.write(contentsOf: message); try handle.close()
        XCTAssertEqual(reader.read([thread], root: root, at: anchor.addingTimeInterval(9)).first?.tokenRate, 20)
        XCTAssertNil(reader.read([thread], root: sessions, at: anchor.addingTimeInterval(9)).first?.tokenRate)
    }

    func testTotalProcessedIncludesInputAndCacheWithoutDoubleCountingCacheOrOutput() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/token-tests-" + UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = sessions.appendingPathComponent("example.jsonl")
        try (record(output: 100, input: 1_000_000, cached: 900_000, after: 0)
            + record(output: 300, input: 1_260_000, cached: 1_159_000, after: 10)).write(to: url)
        let thread = ActiveThread(id: "sample", title: "Example", projectName: "Example", model: "test", effort: "high",
            startedAt: anchor, isSubagent: false, rolloutURL: url, turnID: "one")
        let result = try XCTUnwrap(TokenUsageReader().read([thread], root: root, at: anchor.addingTimeInterval(12)).first)
        XCTAssertEqual(result.tokenRate, 26_020)
        XCTAssertEqual(result.outputTokenRate, 20)
        XCTAssertEqual(result.inputTokenRate, 26_000)
        XCTAssertEqual(result.cachedInputTokenRate, 25_900)
        XCTAssertEqual(Format.tokenRate(result.tokenRate), "~26,0k tok/s")
        XCTAssertEqual(Format.tokenRate(result.outputTokenRate), "~20 tok/s")
    }

    func testPostRequiresVerifiedTiboSourceAndSurvivesForecastReconciliation() throws {
        XCTAssertNil(ResetPost(date: anchor, text: "Example", url: URL(string: "https://example.com/post"), author: "thsottiaux"))
        XCTAssertNil(ResetPost(date: anchor, text: "Example", url: URL(string: "https://x.com/other/status/1"), author: "other"))
        let post = try XCTUnwrap(ResetPost(date: anchor, text: "Reset applied. https://t.co/Example123", url: URL(string: "https://x.com/thsottiaux/status/123"), author: "thsottiaux"))
        XCTAssertEqual(post.readableText, "Reset applied.")
        let forecast = ResetForecast(latest: anchor, probabilityNext7Days: nil, estimatedWindow: nil, sampleSize: 0,
            fetchedAt: anchor, scheduledReset: nil, sourceURL: ResetForecastService.sourceURL, latestAnnouncement: post)
        XCTAssertEqual(forecast.reconcilingQuotaReset(at: anchor.addingTimeInterval(60)).latestAnnouncement, post)
    }
}
