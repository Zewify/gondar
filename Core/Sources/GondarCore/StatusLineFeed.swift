import Foundation

/// One limit from the status line feed, and when a session last genuinely reported it.
public struct FeedEntry: Sendable, Equatable {
    public let limit: UsageLimit
    public let receivedAt: Date

    public init(limit: UsageLimit, receivedAt: Date) {
        self.limit = limit
        self.receivedAt = receivedAt
    }
}

/// The limits Claude Code's status line last reported, each with its own time.
public struct FeedSnapshot: Sendable, Equatable {
    public let entries: [FeedEntry]

    public init(entries: [FeedEntry]) {
        self.entries = entries
    }

    /// Every limit received at the one time.
    public init(receivedAt: Date, limits: [UsageLimit]) {
        entries = limits.map { FeedEntry(limit: $0, receivedAt: receivedAt) }
    }

    public var limits: [UsageLimit] { entries.map(\.limit) }

    /// The entries that count at `now`, each by its own time: received after the last account change (earlier ones may be
    /// another account's) and fresh, that is under `LimitMerge.freshness` old and not from the future.
    public func usable(after lastAccountChange: Date, now: Date) -> [FeedEntry] {
        entries.filter { entry in
            entry.receivedAt > lastAccountChange && (-5 ..< LimitMerge.freshness).contains(now.timeIntervalSince(entry.receivedAt))
        }
    }
}

/// Claude Code pipes its status line command a JSON object on every refresh; its `rate_limits` carry the usage numbers.
public enum StatusLineFeed {
    /// (key in `rate_limits`, kind, scope name, position). Each mapped kind has one fixed position, so ids stay stable.
    private static let mapping: [(key: String, kind: LimitKind, scope: String?, position: Int)] = [
        ("five_hour", .session, nil, 0),
        ("seven_day", .weeklyAll, nil, 1),
        ("seven_day_sonnet", .weeklyScoped, "Sonnet", 2),
        ("seven_day_opus", .weeklyScoped, "Opus", 3),
    ]

    /// Reset times closer than this are one window: the same reset reported a little differently.
    static let sameWindow: TimeInterval = 120
    /// A session not seen for this long is forgotten.
    static let sessionMemory: TimeInterval = 86_400
    /// How often an unchanged session's last-seen time is written, so it is not forgotten while it runs.
    static let seenRefresh: TimeInterval = 3600

    /// The feed file after Claude Code's input `incoming` arrives, or nil when the file should stay as it is.
    ///
    /// Claude Code re-sends a session's last numbers on every refresh, even when the session has not asked Anthropic anything
    /// since, and a session opened before a `/login` keeps sending the previous account's numbers until its next response.
    /// So numbers count only from a genuine report: one whose session's `cost.total_api_duration_ms` rose since that session's
    /// previous input. The file remembers each session as `sessionKey(session_id)` (a hash; the ID itself is never stored)
    /// with its last API duration and when it was last seen, forgetting sessions unseen for a day. A session's first input only
    /// records its baseline.
    ///
    /// A genuine report merges per limit, and moves that limit's own `received_at`: in the same window (reset times under
    /// two minutes apart) the higher number wins, since usage only rises within a window; a later window replaces an earlier one;
    /// an earlier window and a limit the input lacks leave the stored entry, and its time, alone. A missing reset time is an
    /// unknown window: an entry with one replaces a stored entry without; one without replaces only a stored entry that also
    /// lacks one. Input without a session ID or an API duration changes nothing. An unreadable `existing` counts as none.
    public static func mergeStored(existing: Data?, incoming: Data, receivedAt: Date, sessionKey: (String) -> String) -> Data? {
        guard let input = try? JSONSerialization.jsonObject(with: incoming) as? [String: Any],
            let sessionID = input["session_id"] as? String, !sessionID.isEmpty,
            let duration = number((input["cost"] as? [String: Any])?["total_api_duration_ms"]), duration >= 0
        else { return nil }
        let now = receivedAt.timeIntervalSince1970.rounded()
        let old = existing.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        var merged = storedEntries(in: old?["rate_limits"])
        let remembered = storedEntries(in: old?["sessions"])
        var sessions = remembered.filter { now - ($0.value["seen_at"] ?? -.infinity) < sessionMemory }
        var changed = sessions.count != remembered.count

        let key = sessionKey(sessionID)
        let previous = sessions[key]
        let genuine = previous.map { duration > ($0["api_ms"] ?? .infinity) } ?? false
        if previous?["api_ms"] != duration || now - (previous?["seen_at"] ?? -.infinity) >= seenRefresh {
            sessions[key] = ["api_ms": duration, "seen_at": now]
            changed = true
        }

        if genuine {
            for (name, new) in limits(in: input["rate_limits"]) {
                let current = merged[name]
                var entry: [String: Double]
                switch (new["resets_at"].map(seconds), current?["resets_at"].map(seconds)) {
                case (_, nil):
                    // Nothing stored, or the stored window is unknown: the reported entry whole.
                    entry = new
                case (nil, .some):
                    continue
                case let (newReset?, oldReset?):
                    if abs(newReset - oldReset) < sameWindow {
                        entry = current ?? new
                        if let used = new["used_percentage"], used > entry["used_percentage"] ?? -.infinity {
                            entry["used_percentage"] = used
                        }
                    } else if newReset > oldReset {
                        entry = new
                    } else {
                        continue
                    }
                }
                entry["received_at"] = now
                merged[name] = entry
                changed = true
            }
        }
        guard changed else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["rate_limits": merged, "sessions": sessions], options: [.sortedKeys])
    }

    /// The mapped limits in a `rate_limits` value, each with only its finite `used_percentage` and `resets_at`.
    private static func limits(in value: Any?) -> [String: [String: Double]] {
        let source = value as? [String: Any] ?? [:]
        var kept: [String: [String: Double]] = [:]
        for entry in mapping {
            guard let wire = source[entry.key] as? [String: Any] else { continue }
            var fields: [String: Double] = [:]
            for name in ["used_percentage", "resets_at"] {
                if let value = number(wire[name]) { fields[name] = value }
            }
            if !fields.isEmpty { kept[entry.key] = fields }
        }
        return kept
    }

    /// A stored map of name to numbers, keeping only finite numbers; anything unreadable is dropped.
    private static func storedEntries(in value: Any?) -> [String: [String: Double]] {
        let source = value as? [String: Any] ?? [:]
        var kept: [String: [String: Double]] = [:]
        for (name, wire) in source {
            guard let wire = wire as? [String: Any] else { continue }
            let fields = wire.compactMapValues { number($0) }
            if !fields.isEmpty { kept[name] = fields }
        }
        return kept
    }

    /// Unix seconds, given seconds or milliseconds.
    private static func seconds(_ value: Double) -> Double {
        value > 1e11 ? value / 1000 : value
    }

    /// Reads the file `mergeStored` wrote. A missing or null `rate_limits` is an empty feed; a limit that cannot be read,
    /// or has no time of its own (as files from before per-limit times have), is skipped.
    public static func parse(_ data: Data) throws -> FeedSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError("The status line feed is not in the expected shape")
        }
        let source = object["rate_limits"] as? [String: Any] ?? [:]
        let entries = mapping.compactMap { entry -> FeedEntry? in
            guard let wire = source[entry.key] as? [String: Any],
                let used = number(wire["used_percentage"]), abs(used) < 1_000_000,
                let received = number(wire["received_at"])
            else { return nil }
            let limit = UsageLimit(
                kind: entry.kind, scopeName: entry.scope, percent: Int(min(max(used, 0), 100).rounded()), severity: .normal,
                resetsAt: resetDate(wire["resets_at"]), isActive: true, shareOfWeekly: nil, position: entry.position
            )
            return FeedEntry(limit: limit, receivedAt: Date(timeIntervalSince1970: received))
        }
        return FeedSnapshot(entries: entries)
    }

    /// A finite number, given as a JSON number or a numeric string. Booleans are not numbers.
    private static func number(_ value: Any?) -> Double? {
        let result: Double?
        switch value {
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): result = n.doubleValue
        case let s as String: result = Double(s.trimmingCharacters(in: .whitespaces))
        default: result = nil
        }
        guard let result, result.isFinite else { return nil }
        return result
    }

    /// Unix seconds, rounded to the nearest minute; a value above 10^11 is milliseconds.
    private static func resetDate(_ value: Any?) -> Date? {
        guard var seconds = number(value), seconds > 0 else { return nil }
        if seconds > 1e11 { seconds /= 1000 }
        return Date(timeIntervalSince1970: (seconds / 60).rounded() * 60)
    }
}

public enum LimitMerge {
    /// How long a feed entry counts as fresh.
    public static let freshness: TimeInterval = 600

    /// The API's report with every limit in `feed` (the usable feed entries) replacing the API's.
    /// Only the numbers change: the API entry keeps its id, severity, activity and share. In the same window (reset times
    /// under two minutes apart) the higher percentage wins, since usage only rises within a window and either may be behind.
    /// The order is fixed whatever the source: session, weekly all models, scoped limits, then anything else,
    /// each group in the API's order with feed-only entries after, so rows do not jump when the source changes.
    public static func merge(api: UsageReport?, feed: [UsageLimit]) -> UsageReport {
        var limits = api?.limits ?? []

        for fresh in feed {
            let matches: (UsageLimit) -> Bool = { old in
                switch fresh.kind {
                case .weeklyScoped:
                    old.kind == .weeklyScoped && old.scopeName?.caseInsensitiveCompare(fresh.scopeName ?? "") == .orderedSame
                default:
                    old.kind == fresh.kind
                }
            }
            if let first = limits.firstIndex(where: matches) {
                // The feed's entry takes the first match's place; any further match of the same limit goes.
                let old = limits[first]
                let sameWindow = old.resetsAt.flatMap { a in fresh.resetsAt.map { b in abs(a.timeIntervalSince(b)) < StatusLineFeed.sameWindow } } ?? false
                let replaced = UsageLimit(
                    kind: old.kind, scopeName: old.scopeName, percent: sameWindow ? max(old.percent, fresh.percent) : fresh.percent,
                    severity: old.severity, resetsAt: fresh.resetsAt, isActive: old.isActive, shareOfWeekly: old.shareOfWeekly,
                    position: old.position
                )
                limits = limits.enumerated().compactMap { index, entry in
                    index == first ? replaced : (matches(entry) ? nil : entry)
                }
            } else {
                limits.append(fresh)
            }
        }

        func rank(_ limit: UsageLimit) -> Int {
            switch limit.kind {
            case .session: 0
            case .weeklyAll: 1
            case .weeklyScoped: 2
            case .other: 3
            }
        }
        let ordered = limits.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        return UsageReport(limits: ordered, extra: api?.extra)
    }
}

/// What the panel shows, from the last API result and the last feed, for one account.
public enum SnapshotMerge {
    /// The snapshot to show for `account`, or nil when there is nothing to show yet.
    ///
    /// Nothing of another account is ever used: an API snapshot counts only when its profile is `account`'s, a feed entry only
    /// when it arrived after `lastAccountChange` (and is fresh), and the header is the confirmed profile when it is `account`'s,
    /// otherwise `local` (from `~/.claude.json`) when it is. Usable feed entries replace the API's limits and make it live;
    /// feed entries alone are shown when there is a header. `fetchedAt` is the newest time among the API result and the entries used.
    public static func build(
        api: Snapshot?, feed: FeedSnapshot?, lastAccountChange: Date, account: AccountKey?,
        confirmed: (profile: Profile, plan: String?)?, local: Profile?, now: Date
    ) -> Snapshot? {
        guard let account else { return nil }
        let api = api.flatMap { $0.profile.accountKey == account ? $0 : nil }
        let used = feed?.usable(after: lastAccountChange, now: now) ?? []
        guard api != nil || !used.isEmpty else { return nil }

        let header: (profile: Profile, plan: String?)?
        if let confirmed, confirmed.profile.accountKey == account {
            header = confirmed
        } else if let local, local.accountKey == account {
            header = (local, PlanText.label(organizationType: local.organizationType, rateLimitTier: local.rateLimitTier))
        } else {
            header = nil
        }
        guard let profile = api?.profile ?? header?.profile else { return nil }

        let times = [api?.fetchedAt].compactMap { $0 } + used.map(\.receivedAt)
        return Snapshot(
            profile: profile, plan: api != nil ? api?.plan : header?.plan,
            report: LimitMerge.merge(api: api?.report, feed: used.map(\.limit)),
            fetchedAt: times.max() ?? now, source: api?.source ?? .claudeCode, live: !used.isEmpty
        )
    }
}

/// The inputs to what is shown, and the account they belong to. A different account drops the previous one's API result and
/// failure and starts ignoring feed data received before the change; the app treats its launch as such a change, since it
/// cannot know what changed while it was not running.
public struct UsageSources: Sendable {
    public private(set) var account: AccountKey?
    public private(set) var lastAccountChange: Date
    public private(set) var api: Snapshot?
    public private(set) var apiProblem: Problem?
    public var feed: FeedSnapshot?

    public init(now: Date) {
        lastAccountChange = now
    }

    /// Follows `account`; returns true when it differs from the one followed before.
    @discardableResult
    public mutating func follow(_ account: AccountKey?, at now: Date) -> Bool {
        guard account != self.account else { return false }
        self.account = account
        lastAccountChange = now
        api = nil
        apiProblem = nil
        return true
    }

    /// An API result; ignored unless it is the followed account's.
    public mutating func apiAnswered(_ snapshot: Snapshot) {
        guard let account, snapshot.profile.accountKey == account else { return }
        api = snapshot
        apiProblem = nil
    }

    public mutating func apiFailed(_ problem: Problem) {
        apiProblem = problem
    }

    public func snapshot(confirmed: (profile: Profile, plan: String?)?, local: Profile?, now: Date) -> Snapshot? {
        SnapshotMerge.build(
            api: api, feed: feed, lastAccountChange: lastAccountChange, account: account, confirmed: confirmed, local: local, now: now
        )
    }

    /// When the next feed entry now in use stops counting, so what is shown can be worked out again then.
    public func nextExpiry(now: Date) -> Date? {
        feed?.usable(after: lastAccountChange, now: now).map { $0.receivedAt + LimitMerge.freshness }.min()
    }
}
