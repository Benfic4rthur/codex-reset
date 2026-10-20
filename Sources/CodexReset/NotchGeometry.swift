import AppKit

struct NotchGeometry {
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
                  menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                  safeAreaTop: screen.safeAreaInsets.top,
                  notchGap: gap,
                  notchCenterX: gap > 100 ? (left! + right!) / 2 : nil)
    }

    init(screenFrame: CGRect, menuBarHeight: CGFloat, safeAreaTop: CGFloat,
         notchGap: CGFloat, notchCenterX: CGFloat?) {
        self.screenFrame = screenFrame
        isCapsule = notchGap <= 100
        centerX = notchCenterX ?? screenFrame.midX
        if isCapsule {
            gapWidth = 0
            let barHeight = menuBarHeight > 0 ? menuBarHeight : 24
            compactHeight = max(1, min(22, barHeight - 2))
            leftWingWidth = 34
            rightWingWidth = 140
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

    var quotaDiameter: CGFloat { isCapsule ? max(1, compactHeight - 4) : 30 }
    var quotaStrokeWidth: CGFloat { isCapsule ? 1.6 : 2.7 }
    var compactTextScale: CGFloat { isCapsule ? min(1, compactHeight / 22) : 1 }

    func compactWidth(hasActivity: Bool) -> CGFloat {
        leftWingWidth + gapWidth + (isCapsule && !hasActivity ? 0 : rightWingWidth)
    }

    var expandedWidth: CGFloat { isCapsule ? 320 : compactWidth(hasActivity: true) }
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
