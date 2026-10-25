import AppKit

struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let centerX: CGFloat
    let gapWidth: CGFloat
    private(set) var compactHeight: CGFloat
    private(set) var rightWingWidth: CGFloat
    let topInset: CGFloat
    let isCapsule: Bool
    private(set) var leftWingWidth: CGFloat
    private(set) var detailHeight: CGFloat = 132
    private(set) var listDetailHeight: CGFloat = 184
    private var customDetailWidth: CGFloat = 0

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

    var quotaDiameter: CGFloat { min(30, max(8, compactHeight - 4)) }
    var quotaStrokeWidth: CGFloat { min(2.7, quotaDiameter / 10) }
    var capsuleQuotaFontSize: CGFloat { min(17, max(1, compactHeight - 4)) }
    var capsuleActivityFontSize: CGFloat { min(13, max(1, compactHeight - 4)) }

    func fittingActivity(_ thread: ActiveThread?, hasDisclosure: Bool,
                         preferences: DashboardPreferences = DashboardPreferences()) -> Self {
        if isCapsule && preferences == DashboardPreferences() { return self }
        return fittingLayout(rows: thread.map { preferences.exampleRows(for: $0) } ?? [],
            hasDisclosure: hasDisclosure, preferences: preferences)
    }

    func fittingLayout(rows: [[String]], hasDisclosure: Bool, preferences: DashboardPreferences) -> Self {
        var fitted = self
        fitted.detailHeight = preferences.detailHeight + min(300, max(0, preferences.extraDetailHeight))
        fitted.listDetailHeight = fitted.detailHeight + 52
        if let width = preferences.preferredDetailWidth {
            fitted.customDetailWidth = min(max(320, width), max(320, screenFrame.width - 24))
        }
        if let height = preferences.preferredCompactHeight {
            fitted.compactHeight = min(compactHeight, max(isCapsule ? 12 : 20, height))
        }
        if !preferences.showQuota { fitted.leftWingWidth = isCapsule && rows.isEmpty ? 28 : 0 }
        let maximumWidth = min(320, max(1, min(640, screenFrame.width / 2) - fitted.leftWingWidth - gapWidth))
        fitted.rightWingWidth = NotchedActivityLayout.width(rows: rows, hasDisclosure: hasDisclosure,
            maximum: isCapsule ? min(480, screenFrame.width / 2) : maximumWidth, isCapsule: isCapsule)
        if !rows.isEmpty, let width = preferences.preferredActivityWidth {
            fitted.rightWingWidth = min(isCapsule ? min(480, screenFrame.width / 2) : maximumWidth, max(28, width))
        }
        if !preferences.showQuota && rows.isEmpty && !isCapsule { fitted.rightWingWidth = 28 }
        let available = 2 * min(fitted.surfaceCenterX - screenFrame.minX, screenFrame.maxX - fitted.surfaceCenterX) - 8
        fitted.customDetailWidth = min(fitted.customDetailWidth, max(fitted.compactWidth(hasActivity: true), available))
        return fitted
    }

    func compactWidth(hasActivity: Bool) -> CGFloat {
        leftWingWidth + gapWidth + (isCapsule && !hasActivity ? 0 : rightWingWidth)
    }

    func quotaCenterXInDetails(hasActivity: Bool) -> CGFloat {
        let quotaOffset = isCapsule ? leftWingWidth / 2 : leftWingWidth - 12 - quotaDiameter / 2
        return max(16, (expandedWidth - compactWidth(hasActivity: hasActivity)) / 2 + quotaOffset)
    }

    func toolbarRefreshCenterX(hasActivity: Bool) -> CGFloat {
        // Keep the power button reachable when the quota is centered or hidden.
        min(quotaCenterXInDetails(hasActivity: hasActivity), expandedWidth / 2 - 40)
    }

    var expandedWidth: CGFloat {
        let detailMinimum = isCapsule ? 320 : leftWingWidth + gapWidth + 112
        return max(detailMinimum, compactWidth(hasActivity: true), customDetailWidth)
    }
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
