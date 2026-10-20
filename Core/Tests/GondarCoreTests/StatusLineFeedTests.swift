import Foundation
import Testing

@testable import GondarCore

private let received = Date(timeIntervalSince1970: 1_791_990_000)

private func feedJSON(_ rateLimits: String, receivedAt: Int = 1_791_990_000) -> Data {
    Data(#"{"received_at": \#(receivedAt), "rate_limits": \#(rateLimits)}"#.utf8)
}

private func limit(_ kind: LimitKind, _ scope: String?, _ percent: Int, position: Int = 0, resetsAt: Date? = nil) -> UsageLimit {
    UsageLimit(
        kind: kind, scopeName: scope, percent: percent, severity: .normal,
        resetsAt: resetsAt, isActive: true, shareOfWeekly: nil, position: position
    )
}

private func snapshot(_ limits: [UsageLimit], at: Date = received) -> FeedSnapshot {
    FeedSnapshot(receivedAt: at, limits: limits)
}

@Test func extractKeepsOnlyRateLimits() throws {
    let out = try StatusLineFeed.extract(statusLineJSON: fixture("statusline-sample.json"), receivedAt: received)
    let object = try #require(JSONSerialization.jsonObject(with: out) as? [String: Any])
    #expect(Set(object.keys) == ["received_at", "rate_limits"])
    #expect(object["received_at"] as? Int == 1_791_990_000)
    let text = String(decoding: out, as: UTF8.self)
    for secret in ["transcript", "cwd", "/example", "cost", "session_id", "claude-example"] {
        #expect(!text.contains(secret))
    }
    // The stored form parses back.
    #expect(try StatusLineFeed.parse(out).limits.count == 3)
}

@Test func extractRejectsNonObjects() {
    #expect(throws: ParseError.self) { try StatusLineFeed.extract(statusLineJSON: Data("[1]".utf8), receivedAt: received) }
    #expect(throws: ParseError.self) { try StatusLineFeed.extract(statusLineJSON: Data("nope".utf8), receivedAt: received) }
}

@Test func parsesFeed() throws {
    let data = feedJSON(#"{"five_hour": {"used_percentage": 36.4, "resets_at": 1792000029}, "seven_day": {"used_percentage": 12, "resets_at": 1792400031}}"#)
    let feed = try StatusLineFeed.parse(data)
    #expect(feed.receivedAt == received)
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
    #expect(try StatusLineFeed.parse(Data(#"{"received_at": 1791990000}"#.utf8)).limits.isEmpty)
    #expect(try StatusLineFeed.parse(feedJSON("null")).limits.isEmpty)
    #expect(try StatusLineFeed.parse(feedJSON("{}")).limits.isEmpty)
    #expect(throws: ParseError.self) { try StatusLineFeed.parse(Data("{}".utf8)) }
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
    let feed = snapshot([limit(.session, nil, 10, position: 0), limit(.weeklyScoped, "Sonnet", 20, position: 2)])
    let merged = LimitMerge.merge(api: api, feed: feed, feedAccepted: true, now: received.addingTimeInterval(5))
    #expect(merged.report.limits.map(\.percent) == [10, 80, 20])
    #expect(merged.report.limits.count == 3)
}

@Test func apiOnlyLimitsAreKept() {
    let extra = ExtraUsage(used: Money(minor: 1, currency: "USD", exponent: 2), limit: Money(minor: 100, currency: "USD", exponent: 2))
    let api = UsageReport(limits: [
        limit(.weeklyScoped, "Fable", 30, position: 3),
        limit(.weeklyAll, nil, 80, position: 1),
        limit(.session, nil, 90, position: 0),
    ], extra: extra)
    let feed = snapshot([limit(.session, nil, 10), limit(.weeklyScoped, "Sonnet", 20, position: 2)])
    let merged = LimitMerge.merge(api: api, feed: feed, feedAccepted: true, now: received)
    #expect(merged.report.extra == extra)
    // Session, weekly all, then scoped: the API's own first, the feed's new ones after.
    #expect(merged.report.limits.map(\.scopeName) == [nil, nil, "Fable", "Sonnet"])
    #expect(merged.report.limits.map(\.percent) == [10, 80, 30, 20])
}

@Test func staleFeedIsIgnored() {
    let api = UsageReport(limits: [limit(.session, nil, 90)], extra: nil)
    let feed = snapshot([limit(.session, nil, 10)])
    let fresh = LimitMerge.merge(api: api, feed: feed, feedAccepted: true, now: received.addingTimeInterval(599))
    #expect(fresh.live && fresh.report.limits.map(\.percent) == [10])
    let stale = LimitMerge.merge(api: api, feed: feed, feedAccepted: true, now: received.addingTimeInterval(601))
    #expect(!stale.live && stale.report.limits.map(\.percent) == [90])
}

@Test func feedBeforeAccountChangeIsIgnored() {
    let api = UsageReport(limits: [limit(.session, nil, 90)], extra: nil)
    let merged = LimitMerge.merge(api: api, feed: snapshot([limit(.session, nil, 10)]), feedAccepted: false, now: received)
    #expect(!merged.live)
    #expect(merged.report.limits.map(\.percent) == [90])
}

@Test func liveFlag() {
    let api = UsageReport(limits: [limit(.session, nil, 90)], extra: nil)
    #expect(!LimitMerge.merge(api: api, feed: nil, feedAccepted: true, now: received).live)
    // A fresh feed with no limits (no rate_limits yet) is not live.
    #expect(!LimitMerge.merge(api: api, feed: snapshot([]), feedAccepted: true, now: received).live)
    #expect(LimitMerge.merge(api: nil, feed: snapshot([limit(.session, nil, 10)]), feedAccepted: true, now: received).live)
    let none = LimitMerge.merge(api: nil, feed: nil, feedAccepted: true, now: received)
    #expect(none.report.limits.isEmpty && !none.live)
}

@Test func feedIntervalIsFifteenMinutes() {
    #expect(PollSchedule.feedInterval == .seconds(900))
}

@Test func extractWritesOnlyFiniteNumbers() throws {
    let input = Data(#"{"rate_limits": {"five_hour": {"used_percentage": "/Users/x", "resets_at": true}, "seven_day": {"used_percentage": {"a": "/Users/y"}, "resets_at": "1792000000"}, "seven_day_opus": {"used_percentage": 5, "resets_at": 1792000000}}}"#.utf8)
    let out = try StatusLineFeed.extract(statusLineJSON: input, receivedAt: received)
    let text = String(decoding: out, as: UTF8.self)
    #expect(!text.contains("/Users"))
    #expect(!text.contains("true"))
    let limits = try #require((try JSONSerialization.jsonObject(with: out) as? [String: Any])?["rate_limits"] as? [String: Any])
    #expect(Set(limits.keys) == ["seven_day", "seven_day_opus"])
    let day = try #require(limits["seven_day"] as? [String: Any])
    #expect(Set(day.keys) == ["resets_at"] && day["resets_at"] is Double)
}

@Test func futureDatedFeedIsIgnored() {
    let api = UsageReport(limits: [limit(.session, nil, 90)], extra: nil)
    let feed = snapshot([limit(.session, nil, 10)], at: received.addingTimeInterval(3600))
    let merged = LimitMerge.merge(api: api, feed: feed, feedAccepted: true, now: received)
    #expect(!merged.live && merged.report.limits.map(\.percent) == [90])
    #expect(LimitMerge.merge(api: api, feed: snapshot([limit(.session, nil, 10)], at: received.addingTimeInterval(4)), feedAccepted: true, now: received).live)
}

@Test func replacedLimitKeepsTheApiEntryAndIds() {
    let api = UsageReport(limits: [
        UsageLimit(kind: .session, scopeName: nil, percent: 90, severity: .other("warn"), resetsAt: nil, isActive: false, shareOfWeekly: 50, position: 4),
        limit(.weeklyScoped, "Fable", 30, position: 5),
    ], extra: nil)
    let feed = snapshot([limit(.session, nil, 10, position: 0, resetsAt: Date(timeIntervalSince1970: 60)), limit(.weeklyScoped, "Sonnet", 20, position: 2)])
    let merged = LimitMerge.merge(api: api, feed: feed, feedAccepted: true, now: received).report.limits
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
