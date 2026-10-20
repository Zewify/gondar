import Foundation
import Testing

@testable import GondarCore

private let now = Date(timeIntervalSince1970: 1_791_990_000)

private let localProfile = Profile(
    accountUUID: "a", email: "a@example.com", organizationUUID: "o",
    organizationName: "Org", organizationType: "claude_team", rateLimitTier: nil, seatTier: nil)

private func limit(_ kind: LimitKind, _ percent: Int, scope: String? = nil, position: Int = 0) -> UsageLimit {
    UsageLimit(kind: kind, scopeName: scope, percent: percent, severity: .normal,
               resetsAt: nil, isActive: true, shareOfWeekly: nil, position: position)
}

private func api(_ limits: [UsageLimit], at fetchedAt: Date) -> Snapshot {
    Snapshot(
        profile: Profile(
            accountUUID: "a", email: "confirmed@example.com", organizationUUID: "o",
            organizationName: "Confirmed Org", organizationType: "claude_team", rateLimitTier: nil, seatTier: nil),
        plan: "Team", report: UsageReport(limits: limits, extra: nil), fetchedAt: fetchedAt, source: .claudeCode)
}

private func feed(_ limits: [UsageLimit], at receivedAt: Date) -> FeedSnapshot {
    FeedSnapshot(receivedAt: receivedAt, limits: limits)
}

@Test func feedAloneIsLiveUnderTheLocalHeader() throws {
    let shown = try #require(SnapshotMerge.build(
        api: nil, feed: feed([limit(.session, 40)], at: now - 30), feedAccepted: true,
        header: (localProfile, "Team"), now: now))
    #expect(shown.live)
    #expect(shown.profile == localProfile)
    #expect(shown.plan == "Team")
    #expect(shown.fetchedAt == now - 30)
    #expect(shown.report.limits.map(\.percent) == [40])
}

@Test func feedAloneNeedsAHeader() {
    #expect(SnapshotMerge.build(api: nil, feed: feed([limit(.session, 40)], at: now), feedAccepted: true, header: nil, now: now) == nil)
}

@Test func nothingToShowWithoutApiOrUsableFeed() {
    #expect(SnapshotMerge.build(api: nil, feed: nil, feedAccepted: true, header: (localProfile, nil), now: now) == nil)
    #expect(SnapshotMerge.build(api: nil, feed: feed([limit(.session, 40)], at: now), feedAccepted: false,
                                header: (localProfile, nil), now: now) == nil)
    #expect(SnapshotMerge.build(api: nil, feed: feed([], at: now), feedAccepted: true, header: (localProfile, nil), now: now) == nil)
}

@Test func freshFeedReplacesApiNumbersAndKeepsTheConfirmedProfile() throws {
    let shown = try #require(SnapshotMerge.build(
        api: api([limit(.session, 10), limit(.weeklyScoped, 5, scope: "Fable", position: 2)], at: now - 60),
        feed: feed([limit(.session, 40)], at: now - 120), feedAccepted: true,
        header: (localProfile, "Local"), now: now))
    #expect(shown.live)
    #expect(shown.profile.email == "confirmed@example.com")
    #expect(shown.plan == "Team")
    #expect(shown.report.limits.map(\.percent) == [40, 5])
    // The newest of the two.
    #expect(shown.fetchedAt == now - 60)
}

@Test func rejectedFeedLeavesTheApiAlone() throws {
    let shown = try #require(SnapshotMerge.build(
        api: api([limit(.session, 10)], at: now - 60), feed: feed([limit(.session, 40)], at: now - 30), feedAccepted: false,
        header: (localProfile, nil), now: now))
    #expect(!shown.live)
    #expect(shown.report.limits.map(\.percent) == [10])
    #expect(shown.fetchedAt == now - 60)
}

/// After the feed goes quiet its numbers are no longer live, but they still beat older API numbers.
@Test func quietFeedNewerThanTheApiStillShowsItsNumbers() throws {
    let shown = try #require(SnapshotMerge.build(
        api: api([limit(.session, 10)], at: now - 3600), feed: feed([limit(.session, 40)], at: now - 700), feedAccepted: true,
        header: (localProfile, nil), now: now))
    #expect(!shown.live)
    #expect(shown.report.limits.map(\.percent) == [40])
    #expect(shown.fetchedAt == now - 700)
}

@Test func quietFeedOlderThanTheApiIsIgnored() throws {
    let shown = try #require(SnapshotMerge.build(
        api: api([limit(.session, 10)], at: now - 60), feed: feed([limit(.session, 40)], at: now - 700), feedAccepted: true,
        header: (localProfile, nil), now: now))
    #expect(!shown.live)
    #expect(shown.report.limits.map(\.percent) == [10])
}

@Test func quietFeedAloneIsShownButNotLive() throws {
    let shown = try #require(SnapshotMerge.build(
        api: nil, feed: feed([limit(.session, 40)], at: now - 700), feedAccepted: true, header: (localProfile, nil), now: now))
    #expect(!shown.live)
    #expect(shown.fetchedAt == now - 700)
}

@Test func futureFeedIsIgnored() {
    #expect(SnapshotMerge.build(api: nil, feed: feed([limit(.session, 40)], at: now + 60), feedAccepted: true,
                                header: (localProfile, nil), now: now) == nil)
}
