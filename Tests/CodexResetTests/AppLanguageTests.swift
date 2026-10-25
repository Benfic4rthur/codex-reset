import XCTest
@testable import CodexReset

@MainActor
final class AppLanguageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testExistingLayoutMigratesAndLanguagePersistsWithoutResettingLayout() throws {
        let suite = "CodexResetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = DashboardPreferences()
        original.topRows = [[.tokenRate, .model], [.effort]]
        original.detailRows = [[.lastReset, .tiboAnnouncement], [], []]
        original.preferredDetailWidth = 480
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "language") // A saved layout from before language selection existed.
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "displayPreferences")
        let store = DashboardStore(defaults: defaults)
        XCTAssertEqual(store.language, .portuguese)
        XCTAssertEqual(store.preferences, original)
        store.preferences.language = .spanish
        let reopened = DashboardStore(defaults: defaults)
        XCTAssertEqual(reopened.language, .spanish)
        XCTAssertEqual(reopened.preferences.topRows, original.topRows)
        XCTAssertEqual(reopened.preferences.detailRows, original.detailRows)
        XCTAssertEqual(reopened.preferences.preferredDetailWidth, 480)
        reopened.restoreDefaultLayout()
        XCTAssertEqual(reopened.language, .spanish)
        XCTAssertEqual(reopened.preferences.topRows, DashboardPreferences().topRows)
    }

    func testAccountAndResetTextsSwitchImmediatelyWithoutChangingTheReset() {
        let suite = "CodexResetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(defaults: defaults)
        let began = now.addingTimeInterval(-5 * 3_600)
        let quota = QuotaWindow(usedPercent: 6, durationMinutes: 10_080, resetsAt: began.addingTimeInterval(7 * 86_400))
        store.receiveUsage(UsageSnapshot(primary: quota, secondary: nil, availableResets: nil, fetchedAt: now))
        store.preferences.language = .english
        XCTAssertEqual(store.text(for: .weeklyReset, at: now), "In 6d 19h")
        XCTAssertEqual(store.text(for: .lastReset, at: now), "5h ago")
        XCTAssertEqual(store.tr(DashboardField.extraReset.label), "Extra reset")
        XCTAssertEqual(store.text(for: .activeCount), "0 active")
        XCTAssertTrue(store.tokenRateDescription(for: .tokenRate).contains("Input + output"))
        store.preferences.language = .spanish
        XCTAssertEqual(store.text(for: .weeklyReset, at: now), "En 6d 19h")
        XCTAssertEqual(store.text(for: .lastReset, at: now), "hace 5h")
        XCTAssertEqual(store.tr(DashboardField.extraReset.label), "Reinicio extra")
        XCTAssertEqual(store.lastResetNotice?.date, began)
        XCTAssertTrue(store.tokenRateDescription(for: .tokenRate).contains("Entrada + salida"))
    }

    func testForecastWindowsAndExpiredAnnouncementsUseChosenLanguage() {
        let window = EstimatedResetWindow(startsAt: now.addingTimeInterval(86_400), endsAt: now.addingTimeInterval(172_800))
        XCTAssertEqual(window.presentation(at: now, language: .english).headline, "Between 1d 0h\nand 2d 0h")
        XCTAssertEqual(window.presentation(at: now, language: .spanish).caption, "Estimación histórica")
        XCTAssertEqual(window.presentation(at: now, isSmallSample: true, language: .spanish).caption, "Estimación · pocos datos")
        XCTAssertEqual(window.presentation(at: now.addingTimeInterval(172_801), language: .english).headline, "Window ended")
        let announcement = ScheduledResetAnnouncement(announcedAt: now.addingTimeInterval(-600), scheduledFor: now,
            resetType: "regular", text: "Reset", sourceURL: ResetForecastService.sourceURL)
        let forecast = ResetForecast(latest: now.addingTimeInterval(-86_400), probabilityNext7Days: nil,
            estimatedWindow: window, sampleSize: 7, fetchedAt: now, scheduledReset: announcement,
            sourceURL: ResetForecastService.sourceURL)
        XCTAssertEqual(forecast.presentation(at: now, language: .english).headline, "Announced time has passed")
        XCTAssertEqual(forecast.presentation(at: now, language: .spanish).caption, "Esperando confirmación")
        XCTAssertEqual(window.startsAt, now.addingTimeInterval(86_400))
    }

    func testExistingFailureChangesLanguageWithoutAnotherRequest() async {
        let suite = "CodexResetTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(defaults: defaults)
        store.refreshForecast { throw ResetForecastError.unavailable(503) }
        let deadline = Date().addingTimeInterval(3)
        while store.isRefreshingForecast && Date() < deadline { await Task.yield() }
        XCTAssertFalse(store.isRefreshingForecast)
        store.preferences.language = .english
        XCTAssertEqual(store.forecastError, "The reset source is unavailable (HTTP 503).")
        store.preferences.language = .spanish
        XCTAssertEqual(store.forecastError, "La fuente de reinicios no está disponible (HTTP 503).")
        XCTAssertEqual(AppLanguage.english.error(CodexClientError.disconnected), "The connection to Codex was closed.")
        XCTAssertEqual(AppLanguage.spanish.error(ActiveThreadReader.ReadError.databaseUnavailable), "No se ha encontrado el historial local de Codex en este Mac.")
    }

    func testTranslationCacheAndDatesAreSeparatedByLanguage() throws {
        let post = try XCTUnwrap(ResetPost(date: now, text: "Reset announced", url: URL(string: "https://x.com/thsottiaux/status/123"), author: "thsottiaux"))
        XCTAssertNotEqual(AppLanguage.portuguese.translationKey(for: post), AppLanguage.spanish.translationKey(for: post))
        XCTAssertTrue(AppLanguage.spanish.needsAnnouncementTranslation)
        XCTAssertFalse(AppLanguage.english.needsAnnouncementTranslation)
        XCTAssertNotEqual(AppLanguage.english.date(now), AppLanguage.spanish.date(now))
        XCTAssertEqual(Format.tokenRate(26_020, language: .english), "~26.0k tok/s")
        XCTAssertEqual(Format.tokenRate(26_020, language: .spanish), "~26,0k tok/s")
    }

    func testShortModelRemovesOnlyGPTPrefixAndRetainsAllFamilies() {
        for (raw, short) in [("gpt-6.1-sol", "6.1 Sol"), ("gpt-6.1-luna", "6.1 Luna"),
                             ("gpt-6-astra", "6 Astra"), ("gpt-5.6-terra", "5.6 Terra"), ("gpt-6.1", "6.1")] {
            XCTAssertEqual(Format.shortModel(raw), short)
            XCTAssertEqual(Format.model(raw), "GPT-" + short)
        }
        XCTAssertEqual(Format.shortModel("custom-model"), "custom-model")
        XCTAssertEqual(Format.effort("high", language: .spanish), "Alto")
    }

    func testEveryFieldAndCatalogFormatHasEnglishAndSpanishTranslations() {
        for field in DashboardField.allCases { XCTAssertNotNil(AppLanguage.translations[field.label], field.rawValue) }
        for (key, values) in AppLanguage.translations {
            XCTAssertEqual(values.count, 2, key)
            let placeholders = key.filter { $0 == "%" }.count
            for value in values {
                XCTAssertFalse(value.isEmpty, key)
                XCTAssertEqual(value.filter { $0 == "%" }.count, placeholders, key)
            }
        }
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), ["pt-BR", "en", "es"])
    }
}
