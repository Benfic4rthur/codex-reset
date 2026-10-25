import Foundation

/// Reads only token-count metadata. Message contents and tool output are never decoded.
final class TokenUsageReader {
    private struct Point {
        let date: Date
        let output: Int64
        let input: Int64
        let cached: Int64
        let total: Int64
    }
    private struct State {
        var offset: UInt64 = 0
        var partial = Data()
        var points: [Point] = []
        var turnID: String?
    }
    private var states: [String: State] = [:]
    private let lock = NSLock()
    private let maximumRead = 2 * 1_024 * 1_024

    func read(_ threads: [ActiveThread], root: URL, at now: Date) -> [ActiveThread] {
        lock.lock()
        defer { lock.unlock() }
        states = states.filter { key, _ in threads.contains { $0.id == key } }
        let rootPath = root.resolvingSymlinksInPath().path + "/"
        return threads.map { original in
            var thread = original
            thread.tokenRate = nil
            thread.outputTokenRate = nil
            thread.inputTokenRate = nil
            thread.cachedInputTokenRate = nil
            thread.tokenRateSampledAt = nil
            guard let url = thread.rolloutURL?.resolvingSymlinksInPath(),
                  url.path.hasPrefix(rootPath + "sessions/") || url.path.hasPrefix(rootPath + "archived_sessions/"),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  let file = try? FileHandle(forReadingFrom: url) else { return thread }
            defer { try? file.close() }
            var state = states[thread.id] ?? State(turnID: thread.turnID)
            if state.turnID != thread.turnID || UInt64(size) < state.offset { state = State(turnID: thread.turnID) }
            if state.offset == 0 && size > maximumRead {
                state.offset = UInt64(size - maximumRead)
                // Discard a possibly partial first record.
                try? file.seek(toOffset: state.offset)
                if let data = try? file.read(upToCount: maximumRead), let newline = data.firstIndex(of: 0x0A) {
                    state.partial = data.suffix(from: data.index(after: newline))
                    state.offset = UInt64(size)
                }
            } else {
                try? file.seek(toOffset: state.offset)
                if let data = try? file.read(upToCount: maximumRead) {
                    state.offset += UInt64(data.count)
                    state.partial.append(data)
                }
            }
            while let newline = state.partial.firstIndex(of: 0x0A) {
                let line = Data(state.partial.prefix(upTo: newline))
                state.partial.removeSubrange(...newline)
                guard line.range(of: Data("\"token_count\"".utf8)) != nil,
                      let point = Self.decode(line), point.date >= (thread.startedAt ?? .distantPast), point.date <= now else { continue }
                if let previous = state.points.last {
                    guard point.date > previous.date, point.output >= previous.output,
                          point.input >= previous.input, point.cached >= previous.cached, point.total >= previous.total else { continue }
                    // Duplicate usage snapshots aren't new measurements.
                    if point.total == previous.total { continue }
                }
                state.points.append(point)
                state.points = Array(state.points.suffix(2))
            }
            if state.partial.count > maximumRead { state.partial.removeAll() }
            states[thread.id] = state
            if state.points.count == 2 {
                let first = state.points[0], last = state.points[1]
                let elapsed = last.date.timeIntervalSince(first.date)
                if elapsed > 0 && now.timeIntervalSince(last.date) <= 5 * 60 {
                    thread.tokenRate = Double(last.total - first.total) / elapsed
                    thread.outputTokenRate = Double(last.output - first.output) / elapsed
                    thread.inputTokenRate = Double(last.input - first.input) / elapsed
                    thread.cachedInputTokenRate = Double(last.cached - first.cached) / elapsed
                    thread.tokenRateSampledAt = last.date
                }
            }
            return thread
        }
    }

    private static func decode(_ line: Data) -> Point? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line),
              envelope.type == "event_msg", let usage = envelope.payload.usage, usage.output_tokens >= 0 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: envelope.timestamp) ?? ISO8601DateFormatter().date(from: envelope.timestamp)
        let input = usage.input_tokens ?? 0, cached = usage.cached_input_tokens ?? 0
        guard input >= 0, cached >= 0 else { return nil }
        let sum = input.addingReportingOverflow(usage.output_tokens)
        guard !sum.overflow else { return nil }
        let total = usage.total_tokens ?? sum.partialValue
        guard total >= 0 else { return nil }
        return date.map { Point(date: $0, output: usage.output_tokens, input: input, cached: cached, total: total) }
    }

    private struct Envelope: Decodable {
        let type: String
        let timestamp: String
        let payload: Payload
    }
    private struct Payload: Decodable {
        let usage: Info.Usage?
        enum Keys: String, CodingKey { case type, info }
        struct Info: Decodable {
            let total_token_usage: Usage
            struct Usage: Decodable {
                let output_tokens: Int64
                let input_tokens: Int64?
                let cached_input_tokens: Int64?
                let total_tokens: Int64?
            }
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            guard try container.decode(String.self, forKey: .type) == "token_count" else { usage = nil; return }
            usage = try container.decodeIfPresent(Info.self, forKey: .info)?.total_token_usage
        }
    }
}
