import SwiftUI
import XCTest
@testable import CodexReset

final class NotchSurfaceTests: XCTestCase {
    func testExpandedPanelHasTheSameWidthAboveAndBelowThePhysicalNotch() {
        let rect = CGRect(x: 0, y: 0, width: 500, height: 260)
        let closed = NotchSurface(width: 300, compactWidth: 300, compactHeight: 44,
            visibleDepth: 0, isCapsule: false).path(in: rect)
        XCTAssertFalse(closed.contains(CGPoint(x: 50, y: 20)))
        for width: CGFloat in [320, 380, 450] {
            let opened = NotchSurface(width: width, compactWidth: 300, compactHeight: 44,
                visibleDepth: 154, isCapsule: false).path(in: rect)
            let left = rect.midX - width / 2
            let right = rect.midX + width / 2
            for y: CGFloat in [10, 30, 43, 44, 45, 80, 150] {
                XCTAssertTrue(opened.contains(CGPoint(x: left + 0.5, y: y)))
                XCTAssertTrue(opened.contains(CGPoint(x: right - 0.5, y: y)))
                XCTAssertFalse(opened.contains(CGPoint(x: left - 0.5, y: y)))
                XCTAssertFalse(opened.contains(CGPoint(x: right + 0.5, y: y)))
            }
        }
    }

    func testScreenEdgeCurvesFlareIntoTheScreenBorder() {
        let path = NotchSurface(width: 300, compactWidth: 300, compactHeight: 44,
            visibleDepth: 0, isCapsule: false).path(in: CGRect(x: 0, y: 0, width: 400, height: 220))
        XCTAssertTrue(path.contains(CGPoint(x: 48, y: 0.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 352, y: 0.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 48, y: 6)))
        XCTAssertFalse(path.contains(CGPoint(x: 352, y: 6)))
    }

    func testExpandedSurfaceHasOneOutlineAndNoHolesAtTheOldJoin() {
        let rect = CGRect(x: 0, y: 0, width: 500, height: 260)
        for depth: CGFloat in [0.1, 1, 6, 20, 154] {
            let path = NotchSurface(width: 420, compactWidth: 300, compactHeight: 44,
                visibleDepth: depth, isCapsule: false).path(in: rect)
            var moves = 0
            var closes = 0
            path.forEach { element in
                if case .move = element { moves += 1 }
                if case .closeSubpath = element { closes += 1 }
            }
            XCTAssertEqual(moves, 1)
            XCTAssertEqual(closes, 1)
            for x: CGFloat in [101, 110, 250, 390, 399] {
                for y: CGFloat in [43, 44, 44 + depth / 2] {
                    XCTAssertTrue(path.contains(CGPoint(x: x, y: y)), "depth=\(depth), x=\(x), y=\(y)")
                }
            }
        }
        let path = NotchSurface(width: 420, compactWidth: 300, compactHeight: 44,
            visibleDepth: 154, isCapsule: false).path(in: rect)
        XCTAssertTrue(path.contains(CGPoint(x: 41, y: 45))) // No inset or shoulder at the old join.
        XCTAssertTrue(path.contains(CGPoint(x: 41, y: 70)))
    }

    func testCapsuleSurfaceKeepsPreviousOutline() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 180)
        let shape = NotchSurface(width: 352, compactWidth: 104, compactHeight: 22,
            visibleDepth: 82, isCapsule: true).path(in: rect)
        let previous = Path(roundedRect: CGRect(x: 24, y: 0, width: 352, height: 104), cornerRadius: 11)
        for y in stride(from: 0.5, to: 110.0, by: 3) {
            for x in stride(from: 0.5, to: 400.0, by: 3) {
                XCTAssertEqual(shape.contains(CGPoint(x: x, y: y)), previous.contains(CGPoint(x: x, y: y)))
            }
        }
    }
}
