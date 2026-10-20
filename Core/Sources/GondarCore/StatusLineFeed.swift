import Foundation

/// The limits Claude Code's status line last reported, and when.
public struct FeedSnapshot: Sendable, Equatable {
    public let receivedAt: Date
    public let limits: [UsageLimit]

    public init(receivedAt: Date, limits: [UsageLimit]) {
        self.receivedAt = receivedAt
        self.limits = limits
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

    /// Reduces the status line's input to what the feed file may hold: the time and the four limits' two numbers each.
    /// The working folder, transcript path, model, cost and session ID are dropped here.
    public static func extract(statusLineJSON: Data, receivedAt: Date) throws -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: statusLineJSON) as? [String: Any] else {
            throw ParseError("The status line input is not a JSON object")
        }
        return try stored(limits(in: object["rate_limits"]), receivedAt: receivedAt)
    }

    /// Reset times closer than this are one window: the same reset reported a little differently.
    static let sameWindow: TimeInterval = 120

    /// The feed file after Claude Code's input `incoming` arrives, or nil when the file should stay as it is.
    /// Several sessions write the one file, and an idle session re-sends its last numbers on every refresh, so it merges per limit:
    /// in the same window (reset times under two minutes apart) the higher number wins, since usage only rises within a window;
    /// a later window replaces an earlier one; an earlier window and a limit the input lacks leave the stored entry alone.
    /// A missing reset time is an unknown window: an entry with one replaces a stored entry without; one without replaces
    /// only a stored entry that also lacks one. The time moves only when a session reported a stored window or changed an entry.
    /// An unreadable `existing` counts as none.
    public static func mergeStored(existing: Data?, incoming: Data, receivedAt: Date) -> Data? {
        guard let input = try? JSONSerialization.jsonObject(with: incoming) as? [String: Any] else { return nil }
        let reported = limits(in: input["rate_limits"])
        guard !reported.isEmpty else { return nil }
        let old = existing.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        var merged = limits(in: old?["rate_limits"])
        var fresh = false
        for (key, new) in reported {
            let current = merged[key]
            switch (new["resets_at"].map(seconds), current?["resets_at"].map(seconds)) {
            case (_, nil):
                // Nothing stored, or the stored window is unknown: the reported entry whole.
                merged[key] = new
                fresh = true
            case (nil, .some):
                continue
            case let (newReset?, oldReset?):
                if abs(newReset - oldReset) < sameWindow {
                    fresh = true
                    if let used = new["used_percentage"], used > current?["used_percentage"] ?? -.infinity {
                        merged[key]?["used_percentage"] = used
                    }
                } else if newReset > oldReset {
                    merged[key] = new
                    fresh = true
                }
            }
        }
        guard fresh else { return nil }
        return try? stored(merged, receivedAt: receivedAt)
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

    private static func stored(_ limits: [String: [String: Double]], receivedAt: Date) throws -> Data {
        let output: [String: Any] = [
            "received_at": Int(receivedAt.timeIntervalSince1970.rounded()),
            "rate_limits": limits,
        ]
        return try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    }

    /// Unix seconds, given seconds or milliseconds.
    private static func seconds(_ value: Double) -> Double {
        value > 1e11 ? value / 1000 : value
    }

    /// Reads the file `extract` wrote. A missing or null `rate_limits` is an empty feed; a limit that cannot be read is skipped.
    public static func parse(_ data: Data) throws -> FeedSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let received = number(object["received_at"])
        else {
            throw ParseError("The status line feed is not in the expected shape")
        }
        let source = object["rate_limits"] as? [String: Any] ?? [:]
        let limits = mapping.compactMap { entry -> UsageLimit? in
            guard let wire = source[entry.key] as? [String: Any],
                let used = number(wire["used_percentage"]), abs(used) < 1_000_000
            else { return nil }
            return UsageLimit(
                kind: entry.kind, scopeName: entry.scope, percent: Int(min(max(used, 0), 100).rounded()), severity: .normal,
                resetsAt: resetDate(wire["resets_at"]), isActive: true, shareOfWeekly: nil, position: entry.position
            )
        }
        return FeedSnapshot(receivedAt: Date(timeIntervalSince1970: received), limits: limits)
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
    /// How long feed data counts as fresh.
    public static let freshness: TimeInterval = 600

    /// The API's report with every limit the fresh feed knows replaced by the feed's.
    /// `feedAccepted` is false when the feed predates the last account change.
    /// The order is fixed whatever the source: session, weekly all models, scoped limits, then anything else,
    /// each group in the API's order with feed-only entries after, so rows do not jump when the source changes.
    public static func merge(api: UsageReport?, feed: FeedSnapshot?, feedAccepted: Bool, now: Date) -> (report: UsageReport, live: Bool) {
        let usable = feed.flatMap { feedAccepted && (-5 ..< freshness).contains(now.timeIntervalSince($0.receivedAt)) ? $0 : nil }
        let feedLimits = usable?.limits ?? []
        var limits = api?.limits ?? []

        for fresh in feedLimits {
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
                // Only the numbers change: the API entry keeps its id, severity, activity and share.
                let old = limits[first]
                let replaced = UsageLimit(
                    kind: old.kind, scopeName: old.scopeName, percent: fresh.percent, severity: old.severity,
                    resetsAt: fresh.resetsAt, isActive: old.isActive, shareOfWeekly: old.shareOfWeekly, position: old.position
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
        return (UsageReport(limits: ordered, extra: api?.extra), !feedLimits.isEmpty)
    }
}

/// What the panel shows, from the last API result and the last feed, for one account.
public enum SnapshotMerge {
    /// The snapshot to show, or nil when there is nothing to show yet.
    /// A fresh feed's limits replace the API's (`LimitMerge`) and make it live. A feed that has gone quiet is no longer live,
    /// but its numbers still replace older API numbers, so a rate-limited API never brings back numbers older than the feed's.
    /// The header is the API's confirmed profile when there is an API result, otherwise `header`, which the caller takes from
    /// `~/.claude.json` for the same account. `feedAccepted` is false when the feed predates the last account change.
    /// `fetchedAt` is the newer of the two times used.
    public static func build(
        api: Snapshot?, feed: FeedSnapshot?, feedAccepted: Bool, header: (profile: Profile, plan: String?)?, now: Date
    ) -> Snapshot? {
        let accepted = feed.flatMap { feedAccepted && now.timeIntervalSince($0.receivedAt) >= -5 && !$0.limits.isEmpty ? $0 : nil }
        let fresh = accepted.map { now.timeIntervalSince($0.receivedAt) < LimitMerge.freshness } ?? false
        let used = accepted.flatMap { feed in fresh || api.map { feed.receivedAt > $0.fetchedAt } ?? true ? feed : nil }
        guard api != nil || used != nil else { return nil }
        guard let profile = api?.profile ?? header?.profile else { return nil }
        // A quiet feed is merged as of the time it arrived, when it was fresh.
        let merged = LimitMerge.merge(api: api?.report, feed: used, feedAccepted: true, now: fresh ? now : used?.receivedAt ?? now)
        let times = [api?.fetchedAt, used?.receivedAt].compactMap { $0 }
        return Snapshot(
            profile: profile, plan: api != nil ? api?.plan : header?.plan, report: merged.report,
            fetchedAt: times.max() ?? now, source: api?.source ?? .claudeCode, live: fresh
        )
    }
}
