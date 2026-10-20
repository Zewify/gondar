import Foundation

public struct PollSchedule: Sendable, Equatable {
    public static let interval: Duration = .seconds(300)
    /// How often the API is asked while Claude Code's status line feed is fresh: only for what the feed lacks.
    public static let feedInterval: Duration = .seconds(900)
    public static let minimumGap: Duration = .seconds(60)
    private static let longestDelay: Duration = .seconds(1800)

    public var failures: Int

    public init(failures: Int = 0) {
        self.failures = failures
    }

    /// The backoff (300 s doubling per failure, at most 30 min), or a longer Retry-After.
    /// Retry-After only ever lengthens the wait: the usage endpoint answers 429 with `retry-after: 0`.
    public func nextDelay(retryAfter: Duration?) -> Duration {
        let exponent = min(max(failures, 0), 4)
        let backoff = min(Self.interval * (1 << exponent), Self.longestDelay)
        return max(retryAfter ?? .zero, backoff)
    }

    /// The wait after a failed poll, counting it as a failure unless it is `.unauthorized`:
    /// a refused login is fixed locally, by Claude Code writing a new token, so it waits the plain interval.
    public mutating func delay(after problem: Problem, retryAfter: Duration?) -> Duration {
        if problem == .unauthorized { return Self.interval }
        failures += 1
        return nextDelay(retryAfter: retryAfter)
    }

    /// Whether opening the panel or the window asks for a poll: not while backing off after a failure,
    /// because the scheduled retry handles that and an extra request would prolong a rate limit.
    public var pollsWhenViewed: Bool { failures == 0 }

    public static func mayPollNow(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= 60
    }

    /// How long until a poll is allowed: zero when it is allowed now, otherwise the rest of the minute.
    public static func wait(lastAttempt: Date?, now: Date) -> Duration {
        guard let lastAttempt, !mayPollNow(lastAttempt: lastAttempt, now: now) else { return .zero }
        let elapsed = max(0, now.timeIntervalSince(lastAttempt))
        return minimumGap - .milliseconds(Int64((elapsed * 1000).rounded()))
    }

    /// The last attempt saved by an earlier launch, so a relaunch keeps the one-minute floor.
    /// A time in the future means the clock moved back; it counts as now, so the wait is one minute at most.
    public static func restoredLastAttempt(_ stored: Date?, now: Date) -> Date? {
        stored.map { min($0, now) }
    }
}
