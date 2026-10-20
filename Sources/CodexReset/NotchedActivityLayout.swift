import AppKit

enum NotchedActivityLayout {
    static func width(for thread: ActiveThread?, hasDisclosure: Bool, maximum: CGFloat) -> CGFloat {
        guard let thread else { return 0 }
        let projectFont = NSFont.systemFont(ofSize: 9.2, weight: .semibold)
        let modelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        func measure(_ text: String, font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let projectWidth = measure(thread.projectName, font: projectFont) + (hasDisclosure ? 18 : 0)
        let modelWidth = measure(Format.model(thread.model), font: modelFont)
            + measure("·", font: modelFont)
            + measure(Format.effort(thread.effort), font: modelFont) + 6
        // Include 6 points on the left and 8 to clear the rounded right edge.
        return min(maximum, ceil(max(projectWidth, modelWidth) + 14))
    }
}
