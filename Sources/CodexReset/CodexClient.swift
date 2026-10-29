import Foundation

struct QuotaWindow {
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }
}

struct UsageSnapshot {
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let availableResets: Int?
    let fetchedAt: Date

    /// The account's seven-day quota, regardless of which API slot contains it.
    var weeklyWindow: QuotaWindow? {
        [primary, secondary].compactMap { $0 }
            .filter { ($0.durationMinutes ?? 0) >= 7 * 24 * 60 }
            .max { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }
    }

    /// Identify the five-hour window by its duration, never by API slot or plan.
    var fiveHourWindow: QuotaWindow? {
        [primary, secondary].compactMap { $0 }.first { $0.durationMinutes == 300 }
    }

    /// Prefer the weekly allowance for the compact percentage when available.
    var displayedWindow: QuotaWindow? {
        weeklyWindow ?? primary ?? secondary
    }
}

enum CodexClientError: AppLocalizedError {
    case executableMissing
    case disconnected
    case timeout(String)
    case malformedResponse(String)
    case server(String)

    func message(in language: AppLanguage) -> String {
        switch self {
        case .executableMissing:
            return language.text("Não encontrei o executável do Codex neste Mac.")
        case .disconnected:
            return language.text("A conexão com o Codex foi encerrada.")
        case .timeout(let method):
            return language.text("O Codex demorou demais para responder: %@.", method)
        case .malformedResponse(let method):
            return language.text("O Codex retornou dados incompletos: %@.", method)
        case .server(let message):
            return message == "Erro do Codex." ? language.text("Erro do Codex.") : message
        }
    }
}

enum CodexClient {
    private static let usageConnection = UsageRPCConnection()

    static func fetchUsage() throws -> UsageSnapshot {
        guard let executable = executableURL() else {
            throw CodexClientError.executableMissing
        }

        let response = try usageConnection.readRateLimits(executable: executable)
        guard let result = response["result"] as? [String: Any] else {
            throw CodexClientError.malformedResponse("account/rateLimits/read")
        }

        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        let bucket: [String: Any]?
        if let buckets {
            bucket = buckets["codex"]
                ?? buckets.values.first(where: { ($0["limitId"] as? String) == "codex" })
        } else if let legacy = result["rateLimits"] as? [String: Any],
                  (legacy["limitId"] as? String).map({ $0 == "codex" }) ?? true {
            bucket = legacy
        } else {
            bucket = nil
        }
        let primary = quotaWindow(bucket?["primary"])
        let secondary = quotaWindow(bucket?["secondary"])
        guard primary != nil || secondary != nil else {
            throw CodexClientError.malformedResponse("account/rateLimits/read")
        }

        let resetCredits = result["rateLimitResetCredits"] as? [String: Any]
        let count = number(resetCredits?["availableCount"]).map(Int.init)

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            availableResets: count,
            fetchedAt: Date()
        )
    }

    private static func quotaWindow(_ value: Any?) -> QuotaWindow? {
        guard let data = value as? [String: Any],
              let used = number(data["usedPercent"]), used.isFinite else { return nil }
        let duration = number(data["windowDurationMins"]).map(Int.init)
        let reset = number(data["resetsAt"]).map(Date.init(timeIntervalSince1970:))
        return QuotaWindow(usedPercent: used, durationMinutes: duration, resetsAt: reset)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func executableURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            env["CODEX_RESET_CODEX_PATH"],
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex"
        ].compactMap { $0 }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map {
            URL(fileURLWithPath: $0)
        }
    }
}

/// Reuse a single app-server process across quota refreshes. A failed read closes the
/// session and retries once with a fresh process, so sleep/wake and Codex upgrades recover.
private final class UsageRPCConnection {
    private let lock = NSLock()
    private var session: RPCSession?
    private var nextRequestID = 1

    func readRateLimits(executable: URL) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        for attempt in 0..<2 {
            do {
                if session == nil {
                    let newSession = try RPCSession(executable: executable)
                    do {
                        _ = try newSession.request(
                            id: nextID(),
                            method: "initialize",
                            params: [
                                "clientInfo": [
                                    "name": "codex-reset",
                                    "title": "Codex Reset",
                                    "version": "0.1.0"
                                ],
                                "capabilities": [:] as [String: String]
                            ]
                        )
                        try newSession.notify(method: "initialized")
                        session = newSession
                    } catch {
                        newSession.close()
                        throw error
                    }
                }

                return try session!.request(id: nextID(), method: "account/rateLimits/read")
            } catch {
                session?.close()
                session = nil
                if attempt == 1 { throw error }
            }
        }
        throw CodexClientError.disconnected
    }

    private func nextID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }
}

private final class RPCSession {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let condition = NSCondition()
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]
    private var disconnected = false

    init(executable: URL) throws {
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            self?.receive(data)
        }
        try process.run()
    }

    func request(id: Int, method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)

        let deadline = Date().addingTimeInterval(15)
        condition.lock()
        defer { condition.unlock() }
        while responses[id] == nil && !disconnected {
            if !condition.wait(until: deadline) {
                throw CodexClientError.timeout(method)
            }
        }
        guard let response = responses.removeValue(forKey: id) else {
            throw CodexClientError.disconnected
        }
        if let error = response["error"] as? [String: Any] {
            throw CodexClientError.server((error["message"] as? String) ?? "Erro do Codex.")
        }
        return response
    }

    func notify(method: String) throws {
        try send(["method": method])
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func send(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        try input.fileHandleForWriting.write(contentsOf: data + Data([0x0A]))
    }

    private func receive(_ data: Data) {
        condition.lock()
        guard !data.isEmpty else {
            disconnected = true
            condition.broadcast()
            condition.unlock()
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = message["id"] as? Int else { continue }
            responses[id] = message
            condition.broadcast()
        }
        condition.unlock()
    }
}
