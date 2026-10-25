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
    enum ReadError: AppLocalizedError {
        case databaseUnavailable
        case openFailed
        case attachFailed
        case queryFailed

        func message(in language: AppLanguage) -> String {
            switch self {
            case .databaseUnavailable:
                return language.text("Não encontrei o histórico local do Codex neste Mac.")
            case .openFailed, .attachFailed, .queryFailed:
                return language.text("Não foi possível ler as conversas ativas do Codex.")
            }
        }
    }

    static func read() -> [ActiveThread] {
        (try? readThrowing()) ?? []
    }

    // Use this variant when the caller needs to distinguish "no active turns"
    // from a missing or unreadable Codex database.
    static func readThrowing(root: URL? = nil, includeTokenRate: Bool = false) throws -> [ActiveThread] {
        let home = root ?? codexHome
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

        let projects = try projectResolver(connection: connection, home: home)

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
                   COALESCE(NULLIF(TRIM(t.name), ''), NULLIF(TRIM(t.title), ''), ''),
                   COALESCE(t.project_id, ''),
                   COALESCE(NULLIF(t.model, ''), '—'),
                   COALESCE(NULLIF(t.reasoning_effort, ''), '—'),
                   n.started_at,
                   CASE WHEN t.agent_path IS NOT NULL
                             OR t.thread_source = 'subagent'
                             OR t.source LIKE '{"subagent":%'
                        THEN 1 ELSE 0 END,
                   t.tokens_used, t.rollout_path, n.turn_id, t.cwd
            FROM newest_turn AS n
            JOIN main.threads AS t ON t.id = n.thread_id
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
                    projectName: projects.name(threadID: textColumn(statement, 0),
                        projectID: textColumn(statement, 2), cwd: textColumn(statement, 10)) ?? "",
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

    private static func projectResolver(connection: OpaquePointer, home: URL) throws -> ProjectResolver {
        let query = """
            SELECT p.id, p.name, r.path
            FROM main.projects AS p
            LEFT JOIN main.project_roots AS r ON r.project_id = p.id
            ORDER BY length(r.path) DESC, r.position ASC, p.updated_at_ms DESC, p.id
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadError.queryFailed
        }
        defer { sqlite3_finalize(statement) }
        var names: [String: String] = [:]
        var roots: [ProjectResolver.Root] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let id = textColumn(statement, 0)
                names[id] = textColumn(statement, 1)
                let path = textColumn(statement, 2)
                if !path.isEmpty { roots.append(ProjectResolver.Root(projectID: id, path: path)) }
            case SQLITE_DONE:
                return ProjectResolver(codexHome: home, names: names, roots: roots)
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
