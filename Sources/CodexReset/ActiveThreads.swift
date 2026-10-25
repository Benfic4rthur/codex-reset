import Foundation
import SQLite3

struct ActiveThread: Identifiable, Equatable {
    let id: String
    let title: String
    let projectName: String
    let model: String
    let effort: String
    let startedAt: Date?
    let isSubagent: Bool
    var tokensUsed: Int64? = nil
    var tokenRate: Double? = nil
    var outputTokenRate: Double? = nil
    var inputTokenRate: Double? = nil
    var cachedInputTokenRate: Double? = nil
    var tokenRateSampledAt: Date? = nil
    var rolloutURL: URL? = nil
    var turnID: String? = nil
}

enum ActiveThreadReader {
    private static let tokenReader = TokenUsageReader()
    enum ReadError: LocalizedError {
        case databaseUnavailable
        case openFailed
        case attachFailed
        case queryFailed

        var errorDescription: String? {
            switch self {
            case .databaseUnavailable:
                return "Não encontrei o histórico local do Codex neste Mac."
            case .openFailed, .attachFailed, .queryFailed:
                return "Não foi possível ler as conversas ativas do Codex."
            }
        }
    }

    static func read() -> [ActiveThread] {
        (try? readThrowing()) ?? []
    }

    // Use this variant when the caller needs to distinguish "no active turns"
    // from a missing or unreadable Codex database.
    static func readThrowing(includeTokenRate: Bool = false) throws -> [ActiveThread] {
        let home = codexHome
        let stateURL = home.appendingPathComponent("state_5.sqlite")
        let historyURL = home.appendingPathComponent("thread_history_1.sqlite")

        guard FileManager.default.fileExists(atPath: stateURL.path),
              FileManager.default.fileExists(atPath: historyURL.path) else {
            throw ReadError.databaseUnavailable
        }

        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(readOnlyURI(for: stateURL), &connection, flags, nil) == SQLITE_OK,
              let connection else {
            if let connection { sqlite3_close(connection) }
            throw ReadError.openFailed
        }
        defer { sqlite3_close(connection) }

        var attachStatement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "ATTACH DATABASE ? AS history", -1, &attachStatement, nil) == SQLITE_OK,
              let attachStatement else {
            throw ReadError.attachFailed
        }
        let attachResult = readOnlyURI(for: historyURL).withCString { filename in
            sqlite3_bind_text(attachStatement, 1, filename, -1, nil)
            return sqlite3_step(attachStatement)
        }
        sqlite3_finalize(attachStatement)
        guard attachResult == SQLITE_DONE else { throw ReadError.attachFailed }

        // Only the newest turn for a thread can make it active. Looking for any
        // inProgress turn would count stale turns left behind after a later turn.
        let query = """
            WITH newest_turn AS (
                SELECT thread_id, turn_id, status, started_at,
                       ROW_NUMBER() OVER (
                           PARTITION BY thread_id ORDER BY rollout_ordinal DESC
                       ) AS position
                FROM history.thread_turns
            )
            SELECT t.id,
                   COALESCE(NULLIF(TRIM(t.name), ''), NULLIF(TRIM(t.title), ''), 'Conversa sem título'),
                   COALESCE(
                       NULLIF(TRIM(project.name), ''),
                       (
                           SELECT NULLIF(TRIM(root_project.name), '')
                           FROM main.project_roots AS root
                           JOIN main.projects AS root_project ON root_project.id = root.project_id
                           WHERE substr(t.cwd, 1, length(root.path)) = root.path
                             AND (length(t.cwd) = length(root.path)
                                  OR substr(t.cwd, length(root.path) + 1, 1) = '/')
                           ORDER BY length(root.path) DESC, root.position ASC,
                                    root_project.updated_at_ms DESC
                           LIMIT 1
                       ),
                       'Recentes'
                   ),
                   COALESCE(NULLIF(t.model, ''), '—'),
                   COALESCE(NULLIF(t.reasoning_effort, ''), '—'),
                   n.started_at,
                   CASE WHEN t.agent_path IS NOT NULL
                             OR t.thread_source = 'subagent'
                             OR t.source LIKE '{"subagent":%'
                        THEN 1 ELSE 0 END,
                   t.tokens_used, t.rollout_path, n.turn_id
            FROM newest_turn AS n
            JOIN main.threads AS t ON t.id = n.thread_id
            LEFT JOIN main.projects AS project ON project.id = t.project_id
            WHERE n.position = 1 AND n.status = 'inProgress' AND t.archived = 0
            ORDER BY n.started_at DESC, t.id
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ReadError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        var threads: [ActiveThread] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                threads.append(ActiveThread(
                    id: textColumn(statement, 0),
                    title: textColumn(statement, 1),
                    projectName: textColumn(statement, 2),
                    model: textColumn(statement, 3),
                    effort: textColumn(statement, 4),
                    startedAt: sqlite3_column_type(statement, 5) == SQLITE_NULL
                        ? nil
                        : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5))),
                    isSubagent: sqlite3_column_int(statement, 6) != 0,
                    tokensUsed: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 7),
                    rolloutURL: URL(fileURLWithPath: textColumn(statement, 8)),
                    turnID: textColumn(statement, 9)
                ))
            case SQLITE_DONE:
                return includeTokenRate ? tokenReader.read(threads, root: home, at: Date()) : threads
            default:
                throw ReadError.queryFailed
            }
        }
    }

    private static var codexHome: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    private static func readOnlyURI(for url: URL) -> String {
        url.absoluteString + "?mode=ro"
    }

    private static func textColumn(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self))
    }
}
