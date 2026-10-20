import Foundation

public struct PollSchedule: Sendable, Equatable {
    public static let interval: Duration = .seconds(120)
    public static let minimumGap: Duration = .seconds(60)
    private static let longestDelay: Duration = .seconds(1800)

    public var failures: Int

    public init(failures: Int = 0) {
        self.failures = failures
    }

    /// The backoff (120 s doubling per failure, at most 30 min), or a longer Retry-After.
    /// Retry-After only ever lengthens the wait: the usage endpoint answers 429 with `retry-after: 0`.
    public func nextDelay(retryAfter: Duration?) -> Duration {
        let exponent = min(max(failures, 0), 4)
        let backoff = min(Self.interval * (1 << exponent), Self.longestDelay)
        return max(retryAfter ?? .zero, backoff)
    }

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
