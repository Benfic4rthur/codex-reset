import AppKit

enum NotchedActivityLayout {
    static func width(for thread: ActiveThread?, hasDisclosure: Bool, maximum: CGFloat,
                      preferences: DashboardPreferences = DashboardPreferences(), isCapsule: Bool = false) -> CGFloat {
        guard let thread else { return 0 }
        return width(rows: preferences.exampleRows(for: thread), hasDisclosure: hasDisclosure,
            maximum: maximum, isCapsule: isCapsule)
    }

    static func width(rows: [[String]], hasDisclosure: Bool, maximum: CGFloat, isCapsule: Bool) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        func measure(_ text: String, size: CGFloat) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium)]).width
        }
        if isCapsule {
            let cells = Array(rows.joined())
            return min(maximum, ceil(cells.reduce(0) { $0 + measure($1, size: 13) }
                + CGFloat(max(0, cells.count - 1)) * 7 + (hasDisclosure ? 23 : 0) + 16))
        }
        let widths = rows.enumerated().map { index, row in
            row.reduce(CGFloat(0)) { $0 + measure($1, size: rows.count == 1 ? 10 : index == 0 ? 9.2 : 8) }
                + CGFloat(max(0, row.count - 1)) * 5 + (index == 0 && hasDisclosure ? 18 : 0)
        }
        return min(maximum, ceil((widths.max() ?? 0) + 14))
    }
}
