import Foundation

enum DashboardField: String, CaseIterable, Codable, Identifiable {
    case conversation, project, tokenRate, model, effort, activeCount, quota, extraReset, weeklyReset, lastReset
    var id: String { rawValue }
    var label: String {
        switch self {
        case .conversation: return "Conversa"
        case .project: return "Projeto"
        case .tokenRate: return "Tokens por segundo"
        case .model: return "Modelo / agente"
        case .effort: return "Esforço"
        case .activeCount: return "Conversas ativas"
        case .quota: return "Franquia restante"
        case .extraReset: return "Reset extra"
        case .weeklyReset: return "Reset semanal"
        case .lastReset: return "Último reset"
        }
    }
}

enum LayoutRegion { case top, details }
struct DashboardCell: Identifiable, Equatable {
    let field: DashboardField
    let text: String
    var id: DashboardField { field }
}
struct LayoutPosition {
    let region: LayoutRegion
    let row: Int
    let index: Int
}

struct DashboardPreferences: Codable, Equatable {
    var showQuota = true
    var showConversations = true
    var highlightNewReset = true
    var compactModelName = false
    var preferredActivityWidth: Double?
    var preferredDetailWidth: Double?
    var preferredCompactHeight: Double?
    var extraDetailHeight = 0.0
    var topRows: [[DashboardField]] = [[.project], [.model, .effort]]
    var detailRows: [[DashboardField]] = [[.extraReset, .weeklyReset], [.lastReset], []]

    mutating func agentOnly() {
        showQuota = false
        showConversations = false
        compactModelName = true
        topRows = [[.model, .effort], []]
    }

    mutating func place(_ field: DashboardField, in region: LayoutRegion, row: Int,
                        before index: Int? = nil, movingFrom source: LayoutPosition? = nil) {
        let rowCount = region == .top ? 2 : 3
        guard (0..<rowCount).contains(row) else { return }
        if let source { remove(at: source) }
        var rows = region == .top ? topRows : detailRows
        while rows.count < rowCount { rows.append([]) }
        let oldIndex = rows[row].firstIndex(of: field)
        for position in rows.indices { rows[position].removeAll { $0 == field } }
        var destination = index ?? rows[row].count
        if index != nil, source == nil, let oldIndex, oldIndex < destination { destination -= 1 }
        if index != nil, let source, source.region == region, source.row == row, source.index < destination { destination -= 1 }
        rows[row].insert(field, at: max(0, min(destination, rows[row].count)))
        if region == .top { topRows = rows } else { detailRows = rows }
    }

    mutating func remove(at position: LayoutPosition) {
        var rows = position.region == .top ? topRows : detailRows
        guard rows.indices.contains(position.row), rows[position.row].indices.contains(position.index) else { return }
        rows[position.row].remove(at: position.index)
        if position.region == .top { topRows = rows } else { detailRows = rows }
    }

    static func detailRowHeight(_ row: [DashboardField]) -> Double {
        row.contains(.extraReset) || row.contains(.weeklyReset) ? 60 : row == [.lastReset] ? 20 : 36
    }

    var detailHeight: Double {
        let rows = detailRows.filter { !$0.isEmpty }
        let noticeSpace = highlightNewReset && !rows.joined().contains(.lastReset) ? 28.0 : 0
        return 44 + rows.reduce(0) { $0 + Self.detailRowHeight($1) }
            + Double(max(0, rows.count - 1)) * 8 + noticeSpace
    }

    func exampleRows(for thread: ActiveThread) -> [[String]] {
        topRows.map { row in row.map { field in
            switch field {
            case .conversation: return thread.title
            case .project: return thread.projectName
            case .model: return compactModelName ? Format.shortModel(thread.model) : Format.model(thread.model)
            case .effort: return Format.effort(thread.effort)
            case .tokenRate: return thread.tokenRate.map { "~\(Int($0.rounded())) tok/s" } ?? "— tok/s"
            default: return field.label
            }
        }}.filter { !$0.isEmpty }
    }
}

struct LastResetNotice: Codable, Equatable {
    let date: Date
    var presentations = 0
    var isUnseen: Bool { presentations == 0 }
    var isNew: Bool { presentations < 3 }
    mutating func presented() { presentations = min(3, presentations + 1) }
    func elapsed(at now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "agora" }
        if seconds < 3_600 { return "há \(Int(seconds / 60))m" }
        if seconds < 86_400 { return "há \(Int(seconds / 3_600))h" }
        return "há \(Int(seconds / 86_400))d \(Int(seconds / 3_600) % 24)h"
    }
}

/// Cumulative input/output consumption, sampled every five seconds, not generation speed.
struct TokenRateSampler {
    private var previous: [String: (tokens: Int64, turn: Date?, time: Date)] = [:]
    mutating func sample(_ threads: [ActiveThread], at now: Date) -> [ActiveThread] {
        var next: [String: (tokens: Int64, turn: Date?, time: Date)] = [:]
        let result = threads.map { thread in
            var thread = thread
            if let tokens = thread.tokensUsed {
                if let old = previous[thread.id], old.turn == thread.startedAt,
                   now > old.time, now.timeIntervalSince(old.time) <= 15, tokens >= old.tokens {
                    thread.tokenRate = Double(tokens - old.tokens) / now.timeIntervalSince(old.time)
                }
                next[thread.id] = (tokens, thread.startedAt, now)
            }
            return thread
        }
        previous = next
        return result
    }
}
