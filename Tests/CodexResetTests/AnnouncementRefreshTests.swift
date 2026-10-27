import Foundation
import XCTest
@testable import CodexReset

final class AnnouncementRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testObservedResetWithoutAuthorReplacesOlderTweetAcrossEndpointCacheLag() async throws {
        let latest = now.addingTimeInterval(-3_600)
        let observed = record(id: "observed-902", date: latest, type: "observed", status: "902", author: nil,
            text: "A usage reset was observed. Check the source.")
        let older = (1...7).map { index in
            record(id: String(900 - index), date: latest.addingTimeInterval(-Double(index) * 86_400),
                type: "x_post", status: String(900 - index), author: "thsottiaux", text: "An earlier reset announcement.")
        }
        // Either endpoint can still be cached while the other already has the new record.
        for (status, history) in [(observed, [observed] + older), (observed, older), (older[0], [observed] + older)] {
            let loader = try responseLoader(status: status, history: history)
            let result = try await ResetForecastService.fetch(at: now, using: loader)
            let post = try XCTUnwrap(result.latestAnnouncement)
            XCTAssertEqual(post.url.absoluteString, "https://x.com/thsottiaux/status/902")
            XCTAssertTrue(post.isSourceSummary)
            XCTAssertEqual(post.date, latest)
            XCTAssertEqual(post.text, "A usage reset was observed. Check the source.")
            XCTAssertEqual(result.latest, latest)
            XCTAssertEqual(result.sampleSize, 7)
            XCTAssertEqual(result.estimatedWindow?.startsAt, latest.addingTimeInterval(86_400))
            XCTAssertEqual(result.estimatedWindow?.endsAt, latest.addingTimeInterval(86_400))
        }
    }

    func testObservedSourcesStillRequireCanonicalTiboStatusAndCannotImpersonateTweets() throws {
        let canonical = URL(string: "https://x.com/thsottiaux/status/123")!
        let summary = try XCTUnwrap(ResetPost(date: now, text: "A source summary.", url: canonical, author: nil, sourceType: "observed"))
        XCTAssertTrue(summary.isSourceSummary)
        XCTAssertNil(ResetPost(date: now, text: "Unattributed text.", url: canonical, author: nil, sourceType: "x_post"))
        XCTAssertNil(ResetPost(date: now, text: "A source summary.", url: canonical, author: "another", sourceType: "observed"))
        XCTAssertNil(ResetPost(date: now, text: "A source summary.", url: canonical, author: "thsottiaux", sourceType: "unknown"))
        XCTAssertNil(ResetPost(date: now, text: "   ", url: canonical, author: nil, sourceType: "observed"))
        for value in ["http://x.com/thsottiaux/status/123", "https://example.com/thsottiaux/status/123",
                      "https://x.com/another/status/123", "https://x.com/thsottiaux/status/not-a-number",
                      "https://x.com/thsottiaux/status/123/extra", "https://someone@x.com/thsottiaux/status/123",
                      "https://x.com:8443/thsottiaux/status/123"] {
            XCTAssertNil(ResetPost(date: now, text: "A source summary.", url: URL(string: value), author: nil, sourceType: "observed"), value)
        }
        let tracked = try XCTUnwrap(ResetPost(date: now, text: "A source summary.",
            url: URL(string: canonical.absoluteString + "?s=20#tracking"), author: nil, sourceType: "observed"))
        XCTAssertEqual(tracked.url, canonical)
    }

    func testActualTweetReplacesObservedPlaceholderForSameURLInEitherOrder() throws {
        let url = URL(string: "https://x.com/thsottiaux/status/123")!
        let observed = try XCTUnwrap(ResetPost(date: now, text: "A source summary.", url: url, author: nil, sourceType: "observed"))
        let actual = try XCTUnwrap(ResetPost(date: now.addingTimeInterval(-60), text: "The full announcement text.", url: url, author: "thsottiaux"))
        XCTAssertEqual(ResetPost.newest(in: [observed, actual]), actual)
        XCTAssertEqual(ResetPost.newest(in: [actual, observed]), actual)

    }

    func testStatusActualTextBeatsHistoryPlaceholderThroughTheService() async throws {
        let date = now.addingTimeInterval(-60)
        let actual = record(id: "123", date: date, type: "x_post", status: "123", author: "thsottiaux", text: "The full announcement text.")
        let cached = record(id: "observed-123", date: now, type: "observed", status: "123", author: nil, text: "A source summary.")
        let loader = try responseLoader(status: actual, history: [cached])
        let result = try await ResetForecastService.fetch(at: now, using: loader)
        XCTAssertEqual(result.latestAnnouncement?.text, "The full announcement text.")
        XCTAssertEqual(result.latestAnnouncement?.isSourceSummary, false)
    }

    func testTranslationKeysChangeForRevisedTextAndSourceKindButRemainStableForTheSameText() throws {
        let url = URL(string: "https://x.com/thsottiaux/status/123")!
        let initial = try XCTUnwrap(ResetPost(date: now, text: "First announcement.", url: url, author: "thsottiaux"))
        let revised = try XCTUnwrap(ResetPost(date: now, text: "Corrected announcement.", url: url, author: "thsottiaux"))
        let observed = try XCTUnwrap(ResetPost(date: now, text: initial.text, url: url, author: nil, sourceType: "observed"))
        let unchanged = try XCTUnwrap(ResetPost(date: now.addingTimeInterval(60), text: initial.text, url: url, author: "thsottiaux"))
        for language in AppLanguage.allCases {
            XCTAssertNotEqual(language.translationKey(for: initial), language.translationKey(for: revised))
            XCTAssertNotEqual(language.translationKey(for: initial), language.translationKey(for: observed))
            XCTAssertEqual(language.translationKey(for: initial), language.translationKey(for: unchanged))
        }
    }

    @MainActor
    func testManualRefreshPublishesNewAnnouncementDespiteCachedOldTranslation() async throws {
        let suite = "CodexResetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = record(id: "901", date: now.addingTimeInterval(-86_400), type: "x_post", status: "901", author: "thsottiaux", text: "An older announcement.")
        let fresh = record(id: "observed-902", date: now, type: "observed", status: "902", author: nil, text: "A new reset was observed.")
        let oldLoader = try responseLoader(status: old, history: [old])
        let freshLoader = try responseLoader(status: fresh, history: [fresh, old])
        let time = now
        let store = DashboardStore(defaults: defaults)
        store.refreshForecast { try await ResetForecastService.fetch(at: time, using: oldLoader) }
        await waitForRefresh(store)
        let previous = try XCTUnwrap(store.forecast?.latestAnnouncement)
        let previousKey = AppLanguage.portuguese.translationKey(for: previous)
        store.translatedPosts[previousKey] = "Tradução anterior."
        store.refreshForecast { try await ResetForecastService.fetch(at: time, using: freshLoader) }
        await waitForRefresh(store)
        let current = try XCTUnwrap(store.forecast?.latestAnnouncement)
        XCTAssertEqual(current.url.absoluteString, "https://x.com/thsottiaux/status/902")
        XCTAssertTrue(current.isSourceSummary)
        XCTAssertNil(store.translatedPosts[AppLanguage.portuguese.translationKey(for: current)])
        XCTAssertEqual(store.translatedPosts[previousKey], "Tradução anterior.")
        XCTAssertNil(store.forecastError)
    }

    @MainActor
    private func waitForRefresh(_ store: DashboardStore) async {
        let deadline = Date().addingTimeInterval(3)
        while store.isRefreshingForecast && Date() < deadline { await Task.yield() }
        XCTAssertFalse(store.isRefreshingForecast)
    }

    private func record(id: String, date: Date, type: String, status: String, author: String?, text: String) -> [String: Any] {
        var source = ["type": type, "url": "https://x.com/thsottiaux/status/" + status]
        if let author { source["author"] = author }
        return ["id": id, "reset_type": "regular", "announced_at": ISO8601DateFormatter().string(from: date), "text": text, "source": source]
    }

    private func responseLoader(status: [String: Any], history: [[String: Any]]) throws -> @Sendable (URL) async throws -> Data {
        let meta = ["api_version": "v1", "generated_at": ISO8601DateFormatter().string(from: now)]
        let statusData = try JSONSerialization.data(withJSONObject: ["data": ["latest_reset": status], "meta": meta])
        let historyData = try JSONSerialization.data(withJSONObject: ["data": history,
            "pagination": ["has_more": false, "next_cursor": NSNull()], "meta": meta])
        return { url in
            switch url.path {
            case "/api/v1/status": return statusData
            case "/api/v1/resets": return historyData
            default: throw ResetForecastError.invalidResponse
            }
        }
    }
}
