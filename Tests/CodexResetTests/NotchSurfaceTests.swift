import SwiftUI
import XCTest
@testable import CodexReset

final class NotchSurfaceTests: XCTestCase {
    func testOpeningDetailsNeverWidensTheMenuBarSurface() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 180)
        let closed = NotchSurface(width: 350, compactWidth: 350, compactHeight: 36,
            visibleDepth: 0, isCapsule: false).path(in: rect)
        for depth: CGFloat in [1, 20, 102, 154] {
            let opened = NotchSurface(width: 380, compactWidth: 350, compactHeight: 36,
                visibleDepth: depth, isCapsule: false).path(in: rect)
            for y in stride(from: 0.5, to: 36.0, by: 2) {
                for x in stride(from: 0.5, to: 400.0, by: 2) {
                    let point = CGPoint(x: x, y: y)
                    XCTAssertEqual(opened.contains(point), closed.contains(point))
                }
            }
        }
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
