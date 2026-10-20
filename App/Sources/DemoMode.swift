#if DEBUG
import Foundation
import GondarCore

/// Made-up numbers for screenshots and for seeing states the live endpoint will not produce on demand,
/// such as stale numbers: `open -n <Debug app> --args -GondarDemo stale`. Debug builds only; no network at all.
enum DemoMode {
    /// "stale" is the one scenario so far.
    static let scenario = UserDefaults.standard.string(forKey: "GondarDemo")

    static var isEnabled: Bool { scenario != nil }

    /// A fake account with five limits, so all three level colours show: 36, 16 and 2 % low, 62 % medium, 85 % high.
    static func snapshot(now: Date) -> Snapshot {
        let profile = Profile(
            accountUUID: "demo-account", email: "test@example.com", organizationUUID: "demo-organization",
            organizationName: "Demo", organizationType: "claude_max", rateLimitTier: "default_claude_max_20x", seatTier: nil
        )
        func limit(_ kind: LimitKind, _ scope: String?, _ percent: Int, resetsIn hours: Double, position: Int) -> UsageLimit {
            UsageLimit(
                kind: kind, scopeName: scope, percent: percent, severity: .normal,
                resetsAt: now + hours * 3600, isActive: true, shareOfWeekly: nil, position: position
            )
        }
        let limits = [
            limit(.session, nil, 36, resetsIn: 1.1, position: 0),
            limit(.weeklyAll, nil, 16, resetsIn: 5 * 24 + 15, position: 1),
            limit(.weeklyScoped, "Fable", 2, resetsIn: 5 * 24 + 15, position: 2),
            limit(.weeklyScoped, "Opus", 62, resetsIn: 3 * 24 + 4, position: 3),
            limit(.weeklyScoped, "Sonnet", 85, resetsIn: 2 * 24 + 9, position: 4),
        ]
        return Snapshot(
            profile: profile, plan: "Max · Max 20x", report: UsageReport(limits: limits, extra: nil),
            fetchedAt: now - 2 * 60, source: .claudeCode
        )
    }

    /// The state the scenario names: numbers from two minutes ago, kept after a rate-limited poll.
    static func state(now: Date) -> UsageState? {
        guard scenario == "stale" else { return nil }
        let snapshot = snapshot(now: now)
        var state = UsageState()
        state.accountChanged(to: snapshot.profile.accountKey)
        state.received(snapshot)
        state.failed(.rateLimited)
        return state
    }
}
#endif
