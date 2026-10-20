import Foundation

public struct PollSchedule: Sendable, Equatable {
    public static let interval: Duration = .seconds(120)
    public static let minimumGap: Duration = .seconds(60)
    private static let longestDelay: Duration = .seconds(1800)

    public var failures: Int

    public init(failures: Int = 0) {
        self.failures = failures
    }

    public func nextDelay(retryAfter: Duration?) -> Duration {
        if let retryAfter { return max(retryAfter, Self.minimumGap) }
        let exponent = min(max(failures, 0), 4)
        return min(Self.interval * (1 << exponent), Self.longestDelay)
    }

    public static func mayPollNow(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= 60
    }
}
