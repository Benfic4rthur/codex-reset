import AppKit

enum QuotaAllowances: String, Codable, CaseIterable, Identifiable {
    case weekly, fiveHour, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weekly: return "Semanal"
        case .fiveHour: return "5 horas"
        case .both: return "As duas"
        }
    }
}

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

/// Fits both allowances inside the measured menu bar, reserving width for 100%.
struct QuotaPairMetrics {
    let primaryFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let primaryHeight: CGFloat
    let secondaryHeight: CGFloat
    let spacing: CGFloat = 1
    let barHeight: CGFloat = 1
    let contentWidth: CGFloat
    var contentHeight: CGFloat { primaryHeight + secondaryHeight + 2 * spacing + barHeight }

    init(height: CGFloat, expanded: Bool) {
        func lineHeight(_ size: CGFloat) -> CGFloat {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            return ceil(max(font.ascender - font.descender + font.leading,
                ("100%" as NSString).size(withAttributes: [.font: font]).height))
        }
        var size: CGFloat = expanded ? 22 : 20
        func smallSize(_ size: CGFloat) -> CGFloat { size }
        let available = max(3, height - 2)
        while size > 1 && lineHeight(size) + lineHeight(smallSize(size)) + 3 > available { size -= 0.5 }
        primaryFontSize = size
        secondaryFontSize = smallSize(size)
        primaryHeight = lineHeight(size)
        secondaryHeight = lineHeight(secondaryFontSize)
        contentWidth = ceil(max(
            ("100%" as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)]).width,
            ("5h · 100%" as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: secondaryFontSize, weight: .semibold)]).width))
    }
}
