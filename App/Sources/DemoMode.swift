#if DEBUG
import Foundation
import GondarCore

/// Made-up numbers for screenshots and for seeing states the live endpoint will not produce on demand:
/// `open -n <Debug app> --args -GondarDemo live` or `-GondarDemo stale`. Debug builds only; no network at all.
/// zewify.com's screenshots come only from here (`scripts/capture-shots.sh`), never from a real account.
enum DemoMode {
    /// "live": current numbers from Claude Code's status line. "stale": the same numbers two minutes old, after a rate-limited poll.
    static let scenario = UserDefaults.standard.string(forKey: "GondarDemo")

    static var isEnabled: Bool { scenario != nil }

    /// A fake account with five limits, so all three level colours show: 36, 16 and 2 % low, 62 % medium, 85 % high.
    static func snapshot(now: Date, live: Bool = false) -> Snapshot {
        let profile = Profile(
            accountUUID: "demo-account", email: "test@example.com", organizationUUID: "demo-organization",
            organizationName: "Example Org", organizationType: "claude_max", rateLimitTier: "default_claude_max_20x", seatTier: nil
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
            fetchedAt: live ? now : now - 2 * 60, source: .claudeCode, live: live
        )
    }

    /// The state the scenario names, or nil for a name it does not know.
    static func state(now: Date) -> UsageState? {
        guard scenario == "live" || scenario == "stale" else { return nil }
        let snapshot = snapshot(now: now, live: scenario == "live")
        var state = UsageState()
        state.accountChanged(to: snapshot.profile.accountKey)
        state.received(snapshot)
        if scenario == "stale" { state.failed(.rateLimited) }
        return state
    }
}
#endif
