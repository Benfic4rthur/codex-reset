import AppKit

struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let centerX: CGFloat
    let gapWidth: CGFloat
    let compactHeight: CGFloat
    let rightWingWidth: CGFloat
    let topInset: CGFloat
    let isCapsule: Bool
    let leftWingWidth: CGFloat
    let detailHeight: CGFloat = 70
    let listDetailHeight: CGFloat = 102

    init(screen: NSScreen) {
        let left = screen.auxiliaryTopLeftArea?.maxX
        let right = screen.auxiliaryTopRightArea?.minX
        let gap = (left != nil && right != nil) ? max(0, right! - left!) : 0
        self.init(screenFrame: screen.frame,
                  menuBarHeight: Self.menuBarHeight(screenFrame: screen.frame,
                      visibleFrame: screen.visibleFrame, systemThickness: NSStatusBar.system.thickness),
                  safeAreaTop: screen.safeAreaInsets.top,
                  notchGap: gap,
                  notchCenterX: gap > 100 ? (left! + right!) / 2 : nil)
    }

    static func menuBarHeight(screenFrame: CGRect, visibleFrame: CGRect, systemThickness: CGFloat) -> CGFloat {
        let visibleHeight = screenFrame.maxY - visibleFrame.maxY
        // An automatically hidden menu bar may leave only a reveal boundary.
        return visibleHeight > 2 ? visibleHeight : systemThickness
    }

    init(screenFrame: CGRect, menuBarHeight: CGFloat, safeAreaTop: CGFloat,
         notchGap: CGFloat, notchCenterX: CGFloat?) {
        self.screenFrame = screenFrame
        isCapsule = notchGap <= 100
        centerX = notchCenterX ?? screenFrame.midX
        if isCapsule {
            gapWidth = 0
            compactHeight = max(1, menuBarHeight - 2)
            leftWingWidth = 104
            rightWingWidth = 248
            // Keep both rounded edges inside the menu bar, clear of app windows.
            topInset = 1
        } else {
            gapWidth = notchGap > 100 ? notchGap : 160
            leftWingWidth = 48
            rightWingWidth = 112
            let reservedTop = safeAreaTop > 0 ? safeAreaTop : menuBarHeight
            compactHeight = max(24, reservedTop - 2)
            topInset = 0
        }
    }

    var quotaDiameter: CGFloat { 30 }
    var quotaStrokeWidth: CGFloat { 2.7 }
    var capsuleQuotaFontSize: CGFloat { min(17, max(1, compactHeight - 4)) }
    var capsuleActivityFontSize: CGFloat { min(13, max(1, compactHeight - 4)) }

    func compactWidth(hasActivity: Bool) -> CGFloat {
        leftWingWidth + gapWidth + (isCapsule && !hasActivity ? 0 : rightWingWidth)
    }

    var expandedWidth: CGFloat { isCapsule ? max(320, compactWidth(hasActivity: true)) : compactWidth(hasActivity: true) }
    var envelopeWidth: CGFloat { expandedWidth + 8 }
    var envelopeHeight: CGFloat { compactHeight + listDetailHeight + 8 }
    var surfaceCenterX: CGFloat {
        isCapsule ? centerX : centerX + (rightWingWidth - leftWingWidth) / 2
    }
    var frame: CGRect {
        CGRect(x: surfaceCenterX - envelopeWidth / 2,
               y: screenFrame.maxY - topInset - envelopeHeight,
               width: envelopeWidth, height: envelopeHeight)
    }

    func topContains(_ point: CGPoint, hasActivity: Bool) -> Bool {
        let width = compactWidth(hasActivity: hasActivity)
        let x = (envelopeWidth - width) / 2
        return point.x >= x && point.x <= x + width
            && point.y >= envelopeHeight - compactHeight && point.y <= envelopeHeight
    }

    func detailContains(_ point: CGPoint, height: CGFloat) -> Bool {
        let x = (envelopeWidth - expandedWidth) / 2
        return point.x >= x && point.x <= x + expandedWidth
            && point.y >= envelopeHeight - compactHeight - height
            && point.y < envelopeHeight - compactHeight
    }

    func disclosureContains(_ point: CGPoint) -> Bool {
        let rightEdge = (envelopeWidth + compactWidth(hasActivity: true)) / 2
        return point.x >= rightEdge - 26 && point.x <= rightEdge
            && point.y >= envelopeHeight - compactHeight && point.y <= envelopeHeight
    }
}
