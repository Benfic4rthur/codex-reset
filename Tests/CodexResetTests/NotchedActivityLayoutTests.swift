import AppKit
import XCTest
@testable import CodexReset

final class NotchedActivityLayoutTests: XCTestCase {
    private func thread(project: String, model: String = "gpt-6.1-sol", effort: String = "high") -> ActiveThread {
        ActiveThread(id: "example", title: "Example", projectName: project, model: model,
            effort: effort, startedAt: nil, isSubagent: false)
    }

    func testShortContentShrinksAndLongContentGrows() {
        let small = NotchedActivityLayout.width(for: thread(project: "MIRA"), hasDisclosure: false, maximum: 320)
        let long = NotchedActivityLayout.width(for: thread(project: "A considerably longer project name"), hasDisclosure: false, maximum: 320)
        XCTAssertLessThan(small, 112)
        XCTAssertGreaterThan(long, 112)
        XCTAssertGreaterThan(long, small)
        XCTAssertEqual(NotchedActivityLayout.width(for: nil, hasDisclosure: false, maximum: 320), 0)
        XCTAssertEqual(NotchedActivityLayout.width(for: thread(project: String(repeating: "W", count: 200)),
            hasDisclosure: true, maximum: 200), 200)
    }

    func testDisclosureUsesSpaceOnlyWhenItNeedsIt() {
        let sample = thread(project: "A longer project name")
        let without = NotchedActivityLayout.width(for: sample, hasDisclosure: false, maximum: 320)
        let with = NotchedActivityLayout.width(for: sample, hasDisclosure: true, maximum: 320)
        XCTAssertEqual(with - without, 18)
    }

    func testResizeKeepsCameraAndQuotaAnchoredAndDetailsReadable() {
        let base = NotchGeometry(screenFrame: CGRect(x: -100, y: 0, width: 2056, height: 1329),
            menuBarHeight: 39, safeAreaTop: 38, notchGap: 220, notchCenterX: 928)
        for sample in [nil, thread(project: "MIRA"), thread(project: "A considerably longer project name")] {
            let fitted = base.fittingActivity(sample, hasDisclosure: true)
            let compactLeft = fitted.frame.minX + (fitted.envelopeWidth - fitted.compactWidth(hasActivity: sample != nil)) / 2
            XCTAssertEqual(compactLeft + fitted.leftWingWidth + fitted.gapWidth / 2, base.centerX, accuracy: 0.001)
            XCTAssertEqual(fitted.compactHeight, base.compactHeight)
            XCTAssertEqual(fitted.quotaDiameter, base.quotaDiameter)
            XCTAssertGreaterThanOrEqual(fitted.expandedWidth, base.expandedWidth)
        }
    }

    func testCapsuleLayoutRemainsUnchanged() {
        let base = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            menuBarHeight: 24, safeAreaTop: 0, notchGap: 0, notchCenterX: nil)
        XCTAssertEqual(base.fittingActivity(thread(project: "MIRA"), hasDisclosure: true), base)
        XCTAssertEqual(base.fittingActivity(nil, hasDisclosure: false), base)
    }
}
