import SwiftUI
import XCTest
@testable import CodexReset

final class NotchSurfaceTests: XCTestCase {
    func testOpeningDetailsKeepsCompactWidthAboveThePhysicalNotchBottom() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 220)
        let closed = NotchSurface(width: 350, compactWidth: 350, compactHeight: 44,
            visibleDepth: 0, isCapsule: false).path(in: rect)
        for depth: CGFloat in [0.1, 1, 20, 102, 154] {
            let opened = NotchSurface(width: 380, compactWidth: 350, compactHeight: 44,
                visibleDepth: depth, isCapsule: false).path(in: rect)
            // Top curves and straight sides stay fixed; lower compact corners
            // may fill in to join the details instead of leaving transparent holes.
            for y in stride(from: 0.5, to: 24.0, by: 2) {
                for x in stride(from: 0.5, to: 400.0, by: 2) {
                    let point = CGPoint(x: x, y: y)
                    XCTAssertEqual(opened.contains(point), closed.contains(point))
                }
            }
            for y in stride(from: 6.5, to: 44.0, by: 1) {
                XCTAssertFalse(opened.contains(CGPoint(x: 24, y: y)))
                XCTAssertFalse(opened.contains(CGPoint(x: 376, y: y)))
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
        XCTAssertFalse(path.contains(CGPoint(x: 41, y: 45))) // Rounded outer shoulder.
        XCTAssertTrue(path.contains(CGPoint(x: 41, y: 70)))
    }

    func testExtraWidthStartsOnlyBelowMenuBar() {
        let path = NotchSurface(width: 380, compactWidth: 350, compactHeight: 36,
            visibleDepth: 82, isCapsule: false).path(in: CGRect(x: 0, y: 0, width: 400, height: 180))
        XCTAssertFalse(path.contains(CGPoint(x: 15, y: 18)))
        XCTAssertFalse(path.contains(CGPoint(x: 385, y: 18)))
        XCTAssertTrue(path.contains(CGPoint(x: 15, y: 56)))
        XCTAssertTrue(path.contains(CGPoint(x: 385, y: 56)))
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
