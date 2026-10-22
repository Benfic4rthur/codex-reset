import Foundation

enum QuotaResetObservation {
    static func detectedAt(previous: UsageSnapshot?, current: UsageSnapshot,
                           forecast: ResetForecast?) -> Date? {
        guard let quota = current.weeklyWindow, quota.usedPercent.isFinite else { return nil }
        let cycleStart = quota.resetsAt.flatMap { end in
            quota.durationMinutes.map { end.addingTimeInterval(-Double($0) * 60) }
        }

        // A substantial refill before the old weekly deadline is new account
        // evidence, even when the public announcement is still pending.
        if let previous, current.fetchedAt > previous.fetchedAt,
           let old = previous.weeklyWindow, old.durationMinutes == quota.durationMinutes,
           let oldDeadline = old.resetsAt, oldDeadline > current.fetchedAt,
           quota.usedPercent <= 5, old.usedPercent - quota.usedPercent >= 5 {
            if let cycleStart, cycleStart > previous.fetchedAt, cycleStart <= current.fetchedAt {
                return cycleStart
            }
            return current.fetchedAt
        }

        // Also recover a reset that happened while the monitor was closed.
        // A high percentage alone proves nothing: the account's weekly cycle
        // must have started around the expired announcement. Its absolute start
        // keeps repeated queries and restarts from moving the new countdown.
        guard let announcement = forecast?.scheduledReset, announcement.resetType == "regular",
              let scheduled = announcement.scheduledFor, scheduled <= current.fetchedAt,
              let cycleStart, cycleStart >= scheduled, cycleStart <= current.fetchedAt,
              cycleStart.timeIntervalSince(scheduled) <= 24 * 60 * 60 else { return nil }
        return cycleStart
    }
}
