import AppKit

enum QuotaStyle: String, Codable, CaseIterable, Identifiable {
    case compact, largeNumber
    var id: String { rawValue }
    var label: String { self == .compact ? "Compacto" : "Número grande" }
}

/// Fits the real font metrics, including 100%, inside the available menu bar.
struct QuotaNumberMetrics {
    let fontSize: CGFloat
    let textHeight: CGFloat
    let textWidth: CGFloat
    let barHeight: CGFloat
    let barWidth: CGFloat
    let spacing: CGFloat
    let contentHeight: CGFloat
    let contentWidth: CGFloat

    init(height: CGFloat, expanded: Bool, stacked: Bool) {
        barHeight = stacked ? min(2, max(1, height * 0.06)) : min(4, max(1, height * 0.15))
        spacing = stacked ? (expanded ? 1 : 2) : 8
        let padding: CGFloat = stacked ? (expanded ? 2 : 4) : 0
        let availableTextHeight = max(1, height - (stacked ? barHeight + spacing + padding : 0))
        var size: CGFloat = stacked ? (expanded ? 26 : 22) : (expanded ? 24 : 22)
        func lineHeight(_ size: CGFloat) -> CGFloat {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            let drawnHeight = ("100%" as NSString).size(withAttributes: [.font: font]).height
            return ceil(max(font.ascender - font.descender + font.leading, drawnHeight))
        }
        while size > 1 && lineHeight(size) > availableTextHeight { size -= 0.5 }
        fontSize = size
        textHeight = lineHeight(size)
        textWidth = ceil(("100%" as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        ]).width)
        barWidth = stacked ? floor(textWidth * 0.72) : 24
        contentWidth = stacked ? textWidth : textWidth + spacing + barWidth
        contentHeight = stacked ? textHeight + spacing + barHeight : max(textHeight, barHeight)
    }
}
