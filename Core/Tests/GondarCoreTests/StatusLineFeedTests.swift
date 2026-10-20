import Foundation
import Testing

@testable import GondarCore

private let received = Date(timeIntervalSince1970: 1_791_990_000)

/// A stored feed file: every limit given gets `receivedAt` as its own time unless it has one.
private func feedJSON(_ rateLimits: String, receivedAt: Int = 1_791_990_000) -> Data {
    guard var limits = try? JSONSerialization.jsonObject(with: Data(rateLimits.utf8)) as? [String: Any] else {
        return Data(#"{"rate_limits": \#(rateLimits)}"#.utf8)
    }
    for (key, value) in limits {
        if var entry = value as? [String: Any], entry["received_at"] == nil {
            entry["received_at"] = receivedAt
            limits[key] = entry
        }
    }
    return try! JSONSerialization.data(withJSONObject: ["rate_limits": limits])
}

private func limit(_ kind: LimitKind, _ scope: String?, _ percent: Int, position: Int = 0, resetsAt: Date? = nil) -> UsageLimit {
    UsageLimit(
        kind: kind, scopeName: scope, percent: percent, severity: .normal,
        resetsAt: resetsAt, isActive: true, shareOfWeekly: nil, position: position
    )
}

@Test func parsesFeed() throws {
    let data = feedJSON(#"{"five_hour": {"used_percentage": 36.4, "resets_at": 1792000029}, "seven_day": {"used_percentage": 12, "resets_at": 1792400031}}"#)
    let feed = try StatusLineFeed.parse(data)
    #expect(feed.entries.map(\.receivedAt) == [received, received])
    #expect(feed.limits.map(\.kind) == [.session, .weeklyAll])
    #expect(feed.limits.map(\.percent) == [36, 12])
    // Rounded to the nearest minute: ...029 down to ...020, ...031 up to ...040.
    #expect(feed.limits[0].resetsAt == Date(timeIntervalSince1970: 1_792_000_020))
    #expect(feed.limits[1].resetsAt == Date(timeIntervalSince1970: 1_792_400_040))
    #expect(feed.limits.allSatisfy { $0.isActive && $0.severity == .normal && $0.shareOfWeekly == nil })
}

@Test func mapsSonnetAndOpus() throws {
    let data = feedJSON(#"{"five_hour": {"used_percentage": "7.6", "resets_at": 1792000000}, "seven_day_sonnet": {"used_percentage": 40, "resets_at": 1792000000}, "seven_day_opus": {"used_percentage": 5, "resets_at": 1792000000}}"#)
    let feed = try StatusLineFeed.parse(data)
    #expect(feed.limits.map(\.kind) == [.session, .weeklyScoped, .weeklyScoped])
    #expect(feed.limits.map(\.scopeName) == [nil, "Sonnet", "Opus"])
    #expect(feed.limits.map(\.percent) == [8, 40, 5])
    // Stable ids, one fixed position per mapped kind.
    #expect(feed.limits.map(\.id) == ["0:session", "2:weekly_scoped:Sonnet", "3:weekly_scoped:Opus"])
    #expect(LimitText.name(feed.limits[1]) == "Weekly · Sonnet")
}

@Test func skipsNullLimits() throws {
    let data = feedJSON(#"{"five_hour": null, "seven_day": {"used_percentage": null, "resets_at": 1}, "seven_day_sonnet": {"used_percentage": 3, "resets_at": null}, "seven_day_opus": {"resets_at": 1}}"#)
    let feed = try StatusLineFeed.parse(data)
    #expect(feed.limits.map(\.scopeName) == ["Sonnet"])
    #expect(feed.limits[0].resetsAt == nil)
}

@Test func missingRateLimitsIsEmpty() throws {
    #expect(try StatusLineFeed.parse(Data(#"{"sessions": {}}"#.utf8)).limits.isEmpty)
    #expect(try StatusLineFeed.parse(feedJSON("null")).limits.isEmpty)
    #expect(try StatusLineFeed.parse(feedJSON("{}")).limits.isEmpty)
    #expect(throws: ParseError.self) { try StatusLineFeed.parse(Data("[1]".utf8)) }
}

@Test func eachLimitHasItsOwnTime() throws {
    let data = Data(#"{"rate_limits": {"five_hour": {"used_percentage": 10, "received_at": 1791990000}, "seven_day": {"used_percentage": 20, "received_at": 1791990300}}}"#.utf8)
    let feed = try StatusLineFeed.parse(data)
    #expect(feed.entries.map(\.receivedAt) == [received, received + 300])
}

/// A file from before per-limit times has only a file-wide time, which says nothing about each limit: nothing counts.
@Test func limitsWithoutTheirOwnTimeAreSkipped() throws {
    let legacy = Data(#"{"received_at": 1791990000, "rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": 1792000000}}}"#.utf8)
    #expect(try StatusLineFeed.parse(legacy).limits.isEmpty)
}

@Test func millisecondResetsAreTolerated() throws {
    let seconds = try StatusLineFeed.parse(feedJSON(#"{"five_hour": {"used_percentage": 1, "resets_at": 1792000020}}"#))
    let millis = try StatusLineFeed.parse(feedJSON(#"{"five_hour": {"used_percentage": 1, "resets_at": 1792000020000}}"#))
    #expect(seconds.limits[0].resetsAt == millis.limits[0].resetsAt)
    #expect(seconds.limits[0].resetsAt != nil)
}

@Test func feedReplacesApiByKind() {
    let apiReset = Date(timeIntervalSince1970: 1)
    let api = UsageReport(limits: [
        limit(.session, nil, 90, position: 0, resetsAt: apiReset),
        limit(.weeklyAll, nil, 80, position: 1),
        limit(.weeklyScoped, "sonnet", 70, position: 2),
    ], extra: nil)
    let merged = LimitMerge.merge(api: api, feed: [limit(.session, nil, 10, position: 0), limit(.weeklyScoped, "Sonnet", 20, position: 2)])
    #expect(merged.limits.map(\.percent) == [10, 80, 20])
    #expect(merged.limits.count == 3)
}

@Test func apiOnlyLimitsAreKept() {
    let extra = ExtraUsage(used: Money(minor: 1, currency: "USD", exponent: 2), limit: Money(minor: 100, currency: "USD", exponent: 2))
    let api = UsageReport(limits: [
        limit(.weeklyScoped, "Fable", 30, position: 3),
        limit(.weeklyAll, nil, 80, position: 1),
        limit(.session, nil, 90, position: 0),
    ], extra: extra)
    let merged = LimitMerge.merge(api: api, feed: [limit(.session, nil, 10), limit(.weeklyScoped, "Sonnet", 20, position: 2)])
    #expect(merged.extra == extra)
    // Session, weekly all, then scoped: the API's own first, the feed's new ones after.
    #expect(merged.limits.map(\.scopeName) == [nil, nil, "Fable", "Sonnet"])
    #expect(merged.limits.map(\.percent) == [10, 80, 30, 20])
}

/// Usage only rises within a window, so in the same window whichever source is ahead wins; a new window is the feed's.
@Test func sameWindowTakesTheHigherOfApiAndFeed() {
    let reset = Date(timeIntervalSince1970: 1_792_000_000)
    let api = UsageReport(limits: [limit(.session, nil, 60, resetsAt: reset)], extra: nil)
    #expect(LimitMerge.merge(api: api, feed: [limit(.session, nil, 40, resetsAt: reset + 60)]).limits.map(\.percent) == [60])
    #expect(LimitMerge.merge(api: api, feed: [limit(.session, nil, 70, resetsAt: reset)]).limits.map(\.percent) == [70])
    #expect(LimitMerge.merge(api: api, feed: [limit(.session, nil, 5, resetsAt: reset + 18_000)]).limits.map(\.percent) == [5])
    // Without both reset times there is no telling the window: the feed's number.
    #expect(LimitMerge.merge(api: api, feed: [limit(.session, nil, 40)]).limits.map(\.percent) == [40])
}

@Test func usableEntriesAreFreshAndAfterTheAccountChange() {
    let feed = FeedSnapshot(entries: [
        FeedEntry(limit: limit(.session, nil, 10), receivedAt: received),
        FeedEntry(limit: limit(.weeklyAll, nil, 20, position: 1), receivedAt: received - 300),
    ])
    #expect(feed.usable(after: .distantPast, now: received + 299).count == 2)
    // Each by its own time: the older entry goes stale first.
    #expect(feed.usable(after: .distantPast, now: received + 301).map(\.limit.percent) == [10])
    #expect(feed.usable(after: .distantPast, now: received + 601).isEmpty)
    // An entry received before the switch is ignored even though another entry is newer.
    #expect(feed.usable(after: received - 1, now: received + 10).map(\.limit.percent) == [10])
    #expect(feed.usable(after: received, now: received + 10).isEmpty)
    // Future-dated by more than a few seconds: ignored.
    #expect(FeedSnapshot(receivedAt: received + 3600, limits: [limit(.session, nil, 1)]).usable(after: .distantPast, now: received).isEmpty)
    #expect(FeedSnapshot(receivedAt: received + 4, limits: [limit(.session, nil, 1)]).usable(after: .distantPast, now: received).count == 1)
}

@Test func feedIntervalIsFifteenMinutes() {
    #expect(PollSchedule.feedInterval == .seconds(900))
}

@Test func replacedLimitKeepsTheApiEntryAndIds() {
    let api = UsageReport(limits: [
        UsageLimit(kind: .session, scopeName: nil, percent: 90, severity: .other("warn"), resetsAt: nil, isActive: false, shareOfWeekly: 50, position: 4),
        limit(.weeklyScoped, "Fable", 30, position: 5),
    ], extra: nil)
    let merged = LimitMerge.merge(api: api, feed: [limit(.session, nil, 10, position: 0, resetsAt: Date(timeIntervalSince1970: 60)), limit(.weeklyScoped, "Sonnet", 20, position: 2)]).limits
    let ids = merged.map(\.id)
    #expect(Set(ids).count == ids.count)
    let session = merged[0]
    #expect(session.id == api.limits[0].id)
    #expect(session.percent == 10 && session.resetsAt == Date(timeIntervalSince1970: 60))
    #expect(session.severity == .other("warn") && !session.isActive && session.shareOfWeekly == 50)
    #expect(merged.last?.id == "2:weekly_scoped:Sonnet")
}

@Test func percentIsClampedAndNonPositiveResetsDropped() throws {
    let feed = try StatusLineFeed.parse(feedJSON(#"{"five_hour": {"used_percentage": 140, "resets_at": 0}, "seven_day": {"used_percentage": -3, "resets_at": -5}}"#))
    #expect(feed.limits.map(\.percent) == [100, 0])
    #expect(feed.limits.allSatisfy { $0.resetsAt == nil })
}

// MARK: - Merging into the stored file

/// A visible stand-in for the hash the tool uses, so tests can see which session an entry belongs to.
private func key(_ id: String) -> String { "hash(\(id))" }

/// Claude Code's input for session `session` after `apiMs` of API time.
private func statusLine(_ rateLimits: String, session: String = "s", apiMs: Int) -> Data {
    Data(#"{"cwd": "/example", "session_id": "\#(session)", "cost": {"total_cost_usd": 1, "total_api_duration_ms": \#(apiMs)}, "rate_limits": \#(rateLimits)}"#.utf8)
}

private func merge(_ existing: Data?, _ incoming: Data, at time: Date) -> Data? {
    StatusLineFeed.mergeStored(existing: existing, incoming: incoming, receivedAt: time, sessionKey: key)
}

private func stored(_ data: Data?) throws -> (limits: [String: [String: Double]], sessions: [String: [String: Double]]) {
    let bytes = try #require(data)
    let object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let limits = try #require(object["rate_limits"] as? [String: [String: Double]])
    let sessions = try #require(object["sessions"] as? [String: [String: Double]])
    return (limits, sessions)
}

private let t0 = Date(timeIntervalSince1970: 1_791_990_000)
private let later = Date(timeIntervalSince1970: 1_791_990_600)

/// A file in which session "s" was last seen at t0 with 1000 ms of API time, holding `rateLimits` received at t0.
private func seen(_ rateLimits: String = "{}", apiMs: Int = 1000) -> Data {
    var object = try! JSONSerialization.jsonObject(with: feedJSON(rateLimits)) as! [String: Any]
    object["sessions"] = [key("s"): ["api_ms": apiMs, "seen_at": 1_791_990_000]]
    return try! JSONSerialization.data(withJSONObject: object)
}

@Test func firstSightingOnlyRecordsABaseline() throws {
    let file = try stored(merge(nil, statusLine(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000000}}"#, apiMs: 500), at: t0))
    #expect(file.limits.isEmpty)
    #expect(file.sessions == [key("s"): ["api_ms": 500, "seen_at": 1_791_990_000]])
}

@Test func aHigherApiDurationCounts() throws {
    let file = try stored(merge(seen(), statusLine(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000000}}"#, apiMs: 1500), at: later))
    #expect(file.limits["five_hour"] == ["used_percentage": 40, "resets_at": 1_792_000_000, "received_at": 1_791_990_600])
    #expect(file.sessions[key("s")] == ["api_ms": 1500, "seen_at": 1_791_990_600])
}

/// An idle session re-sends its last response's numbers on every refresh; they are not news, and must not look fresh.
@Test func anIdleResendRefreshesNothing() throws {
    let existing = seen(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000000}}"#)
    #expect(merge(existing, statusLine(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000000}}"#, apiMs: 1000), at: later) == nil)
    // Even with different numbers: an unchanged API time means the session asked nothing, so they are old (another account's, say).
    #expect(merge(existing, statusLine(#"{"five_hour": {"used_percentage": 90, "resets_at": 1792018000}}"#, apiMs: 1000), at: later) == nil)
}

@Test func aLowerApiDurationIsANewBaseline() throws {
    let file = try stored(merge(seen(), statusLine(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000000}}"#, apiMs: 10), at: later))
    #expect(file.limits.isEmpty)
    #expect(file.sessions[key("s")]?["api_ms"] == 10)
}

@Test func onlyTheReportedLimitMovesItsTime() throws {
    let existing = seen(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000000}, "seven_day": {"used_percentage": 12, "resets_at": 1792400000}}"#)
    let file = try stored(merge(existing, statusLine(#"{"five_hour": {"used_percentage": 41, "resets_at": 1792000000}}"#, apiMs: 2000), at: later))
    #expect(file.limits["five_hour"] == ["used_percentage": 41, "resets_at": 1_792_000_000, "received_at": 1_791_990_600])
    #expect(file.limits["seven_day"] == ["used_percentage": 12, "resets_at": 1_792_400_000, "received_at": 1_791_990_000])
}

@Test func sessionsUnseenForADayAreForgotten() throws {
    var object = try JSONSerialization.jsonObject(with: seen()) as! [String: Any]
    object["sessions"] = [
        key("old"): ["api_ms": 1, "seen_at": 1_791_990_600 - 86_400],
        key("recent"): ["api_ms": 1, "seen_at": 1_791_990_600 - 86_399],
    ]
    let existing = try JSONSerialization.data(withJSONObject: object)
    let file = try stored(merge(existing, statusLine("{}", session: "new", apiMs: 1), at: later))
    #expect(Set(file.sessions.keys) == [key("recent"), key("new")])
}

/// An unchanged session is written again only once an hour, so it is not forgotten while it runs.
@Test func anUnchangedSessionIsRefreshedHourly() throws {
    #expect(merge(seen(), statusLine("{}", apiMs: 1000), at: t0 + 3599) == nil)
    let file = try stored(merge(seen(), statusLine("{}", apiMs: 1000), at: t0 + 3600))
    #expect(file.sessions[key("s")] == ["api_ms": 1000, "seen_at": 1_791_993_600])
}

@Test func theFileHoldsNoSessionIDOrAnythingElseFromTheInput() throws {
    let input = try fixture("statusline-sample.json")
    var object = try #require(try JSONSerialization.jsonObject(with: input) as? [String: Any])
    object["cost"] = ["total_cost_usd": 1.23, "total_api_duration_ms": 900]
    let out = try #require(StatusLineFeed.mergeStored(
        existing: seen(apiMs: 100), incoming: try JSONSerialization.data(withJSONObject: object), receivedAt: later, sessionKey: { _ in key("s") }))
    let text = String(decoding: out, as: UTF8.self)
    for secret in ["transcript", "cwd", "/example", "cost", "session_id", "claude-example", "00000000-0000", "total"] {
        #expect(!text.contains(secret), "the file contains \(secret)")
    }
    #expect(Set((try JSONSerialization.jsonObject(with: out) as? [String: Any])?.keys ?? [:].keys) == ["rate_limits", "sessions"])
    #expect(try StatusLineFeed.parse(out).limits.count == 3)
}

@Test func inputWithoutASessionOrApiTimeChangesNothing() {
    let existing = seen()
    for input in [
        #"{"cwd": "/example"}"#, "not json", #"{"rate_limits": {"five_hour": {"used_percentage": 1}}}"#,
        #"{"session_id": "s", "rate_limits": {"five_hour": {"used_percentage": 1}}}"#,
        #"{"session_id": "", "cost": {"total_api_duration_ms": 5000}}"#,
        #"{"session_id": "s", "cost": {"total_api_duration_ms": "lots"}}"#,
    ] {
        #expect(merge(existing, Data(input.utf8), at: later) == nil)
        #expect(merge(nil, Data(input.utf8), at: later) == nil)
    }
}

@Test func mergeWritesOnlyFiniteNumbers() throws {
    let input = statusLine(#"{"five_hour": {"used_percentage": "/Users/x", "resets_at": true}, "seven_day": {"used_percentage": {"a": "/Users/y"}, "resets_at": "1792000000"}, "seven_day_opus": {"used_percentage": 5, "resets_at": 1792000000}}"#, apiMs: 2000)
    let out = try #require(merge(seen(), input, at: later))
    let text = String(decoding: out, as: UTF8.self)
    #expect(!text.contains("/Users"))
    #expect(!text.contains("true"))
    let limits = try stored(out).limits
    #expect(Set(limits.keys) == ["seven_day", "seven_day_opus"])
    #expect(Set(limits["seven_day"]?.keys ?? [:].keys) == ["resets_at", "received_at"])
}

@Test func mergeKeepsTheHigherNumberInTheSameWindow() throws {
    let existing = seen(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000000}}"#)
    // Another session, behind this one, genuinely reports a lower number for the same window.
    let lower = try stored(merge(existing, statusLine(#"{"five_hour": {"used_percentage": 20, "resets_at": 1792000010}}"#, apiMs: 2000), at: later))
    #expect(lower.limits["five_hour"] == ["used_percentage": 40, "resets_at": 1_792_000_000, "received_at": 1_791_990_600])
    let higher = try stored(merge(existing, statusLine(#"{"five_hour": {"used_percentage": 55, "resets_at": 1792000000}}"#, apiMs: 2000), at: later))
    #expect(higher.limits["five_hour"]?["used_percentage"] == 55)
}

@Test func mergeTakesANewWindowAndIgnoresAnOlderOne() throws {
    let existing = seen(#"{"five_hour": {"used_percentage": 90, "resets_at": 1792000000}}"#)
    let newer = try stored(merge(existing, statusLine(#"{"five_hour": {"used_percentage": 3, "resets_at": 1792018000}}"#, apiMs: 2000), at: later))
    #expect(newer.limits["five_hour"] == ["used_percentage": 3, "resets_at": 1_792_018_000, "received_at": 1_791_990_600])
    // An older window leaves the entry and its time alone; only the session's baseline moves.
    let older = try stored(merge(existing, statusLine(#"{"five_hour": {"used_percentage": 99, "resets_at": 1791982000}}"#, apiMs: 2000), at: later))
    #expect(older.limits["five_hour"] == ["used_percentage": 90, "resets_at": 1_792_000_000, "received_at": 1_791_990_000])
}

@Test func mergeTreatsACorruptFileAsNone() throws {
    let incoming = statusLine(#"{"five_hour": {"used_percentage": 5, "resets_at": 1792000000}}"#, apiMs: 2000)
    for existing in [Data("{trunc".utf8), Data(#"{"rate_limits": 4, "sessions": 5}"#.utf8), Data()] {
        let file = try stored(merge(existing, incoming, at: later))
        // The session is new to an unreadable file, so this is its baseline.
        #expect(file.limits.isEmpty)
        #expect(file.sessions[key("s")]?["api_ms"] == 2000)
    }
}

@Test func mergeComparesWindowsWithinTwoMinutes() throws {
    // 1792000049 and 1792000050 are 1 s apart across :30 (1792000020 + 30), so minute rounding would split them; they are one window.
    let existing = seen(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000049}}"#)
    func five(_ input: String) throws -> [String: Double]? {
        try stored(merge(existing, statusLine(input, apiMs: 2000), at: later)).limits["five_hour"]
    }
    #expect(try five(#"{"five_hour": {"used_percentage": 20, "resets_at": 1792000050}}"#)?["used_percentage"] == 40)
    // 119 s later is still the same window; 120 s later is a new one.
    #expect(try five(#"{"five_hour": {"used_percentage": 20, "resets_at": 1792000168}}"#)?["used_percentage"] == 40)
    #expect(try five(#"{"five_hour": {"used_percentage": 20, "resets_at": 1792000169}}"#)?["resets_at"] == 1_792_000_169)
    // 119 s earlier is the same window; 120 s earlier is an older one, left alone.
    #expect(try five(#"{"five_hour": {"used_percentage": 60, "resets_at": 1791999930}}"#)?["used_percentage"] == 60)
    #expect(try five(#"{"five_hour": {"used_percentage": 60, "resets_at": 1791999929}}"#)?["received_at"] == 1_791_990_000)
}

@Test func mergeTreatsAMissingResetTimeAsAnUnknownWindow() throws {
    let unknown = seen(#"{"five_hour": {"used_percentage": 40}}"#)
    // Incoming has a reset time, stored does not: the incoming entry whole.
    let taken = try stored(merge(unknown, statusLine(#"{"five_hour": {"used_percentage": 10, "resets_at": 1792000000}}"#, apiMs: 2000), at: later))
    #expect(taken.limits["five_hour"] == ["used_percentage": 10, "resets_at": 1_792_000_000, "received_at": 1_791_990_600])
    // Neither has one: newest wins.
    let newest = try stored(merge(unknown, statusLine(#"{"five_hour": {"used_percentage": 10}}"#, apiMs: 2000), at: later))
    #expect(newest.limits["five_hour"] == ["used_percentage": 10, "received_at": 1_791_990_600])
    // Incoming lacks one, stored has one: stored stays.
    let known = seen(#"{"five_hour": {"used_percentage": 40, "resets_at": 1792000000}}"#)
    let kept = try stored(merge(known, statusLine(#"{"five_hour": {"used_percentage": 90}}"#, apiMs: 2000), at: later))
    #expect(kept.limits["five_hour"]?["received_at"] == 1_791_990_000)
}
