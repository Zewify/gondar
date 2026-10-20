import Foundation
import Testing

@testable import GondarCore

private let now = Date(timeIntervalSince1970: 1_791_990_000)
private let switched = now - 3600
private let mine = AccountKey(accountUUID: "a", organizationUUID: "o")
private let theirs = AccountKey(accountUUID: "b", organizationUUID: "o")

private func profile(_ account: AccountKey, email: String) -> Profile {
    Profile(accountUUID: account.accountUUID, email: email, organizationUUID: account.organizationUUID,
            organizationName: "Org", organizationType: "claude_team", rateLimitTier: nil, seatTier: nil)
}

private let local = profile(mine, email: "local@example.com")
private let confirmed = (profile: profile(mine, email: "confirmed@example.com"), plan: Optional("Confirmed plan"))

private func limit(_ kind: LimitKind, _ percent: Int, scope: String? = nil, position: Int = 0) -> UsageLimit {
    UsageLimit(kind: kind, scopeName: scope, percent: percent, severity: .normal,
               resetsAt: nil, isActive: true, shareOfWeekly: nil, position: position)
}

private func api(_ limits: [UsageLimit], at fetchedAt: Date, account: AccountKey = mine) -> Snapshot {
    Snapshot(profile: profile(account, email: "api@example.com"), plan: "Team",
             report: UsageReport(limits: limits, extra: nil), fetchedAt: fetchedAt, source: .claudeCode)
}

private func feed(_ limits: [UsageLimit], at receivedAt: Date) -> FeedSnapshot {
    FeedSnapshot(receivedAt: receivedAt, limits: limits)
}

private func build(api: Snapshot? = nil, feed: FeedSnapshot? = nil, account: AccountKey? = mine,
                   confirmed: (profile: Profile, plan: String?)? = nil, local: Profile? = local) -> Snapshot? {
    SnapshotMerge.build(api: api, feed: feed, lastAccountChange: switched, account: account,
                        confirmed: confirmed, local: local, now: now)
}

@Test func feedAloneIsLiveUnderTheLocalHeader() throws {
    let shown = try #require(build(feed: feed([limit(.session, 40)], at: now - 30)))
    #expect(shown.live)
    #expect(shown.profile == local)
    #expect(shown.plan == "Team")
    #expect(shown.fetchedAt == now - 30)
    #expect(shown.report.limits.map(\.percent) == [40])
}

@Test func theConfirmedProfileWinsOverTheLocalOne() throws {
    let shown = try #require(build(feed: feed([limit(.session, 40)], at: now), confirmed: confirmed))
    #expect(shown.profile.email == "confirmed@example.com")
    #expect(shown.plan == "Confirmed plan")
}

@Test func feedAloneNeedsAHeaderOfThisAccount() {
    let fresh = feed([limit(.session, 40)], at: now)
    #expect(build(feed: fresh, local: nil) == nil)
    // Another account's local profile or confirmed profile is never used.
    #expect(build(feed: fresh, local: profile(theirs, email: "theirs@example.com")) == nil)
    #expect(build(feed: fresh, confirmed: (profile(theirs, email: "theirs@example.com"), "Max"), local: nil) == nil)
    let shown = build(feed: fresh, confirmed: (profile(theirs, email: "theirs@example.com"), "Max"))
    #expect(shown?.profile == local)
}

@Test func anotherAccountsApiSnapshotIsNeverUsed() {
    #expect(build(api: api([limit(.session, 10)], at: now, account: theirs)) == nil)
    let shown = build(api: api([limit(.session, 10)], at: now, account: theirs), feed: feed([limit(.session, 40)], at: now))
    #expect(shown?.profile == local)
    #expect(shown?.report.limits.map(\.percent) == [40])
}

@Test func nothingWithoutAnAccount() {
    #expect(build(api: api([limit(.session, 10)], at: now), feed: feed([limit(.session, 40)], at: now), account: nil) == nil)
}

@Test func nothingToShowWithoutApiOrUsableFeed() {
    #expect(build() == nil)
    #expect(build(feed: feed([], at: now)) == nil)
    #expect(build(feed: feed([limit(.session, 40)], at: now - 601)) == nil)
}

@Test func aFeedEntryFromBeforeTheSwitchIsIgnored() throws {
    let mixed = FeedSnapshot(entries: [
        FeedEntry(limit: limit(.session, 40), receivedAt: now - 10),
        FeedEntry(limit: limit(.weeklyAll, 77, position: 1), receivedAt: switched - 1),
    ])
    let shown = try #require(build(api: api([limit(.session, 10), limit(.weeklyAll, 20, position: 1)], at: now - 60), feed: mixed))
    #expect(shown.report.limits.map(\.percent) == [40, 20])
    #expect(build(feed: feed([limit(.session, 40)], at: switched)) == nil)
}

@Test func freshFeedReplacesApiNumbersAndKeepsTheApiProfile() throws {
    let shown = try #require(build(
        api: api([limit(.session, 10), limit(.weeklyScoped, 5, scope: "Fable", position: 2)], at: now - 60),
        feed: feed([limit(.session, 40)], at: now - 120), confirmed: confirmed))
    #expect(shown.live)
    #expect(shown.profile.email == "api@example.com")
    #expect(shown.plan == "Team")
    #expect(shown.report.limits.map(\.percent) == [40, 5])
    // The newest of the times used.
    #expect(shown.fetchedAt == now - 60)
}

@Test func aQuietFeedLeavesTheApiAlone() throws {
    let shown = try #require(build(api: api([limit(.session, 10)], at: now - 3600), feed: feed([limit(.session, 40)], at: now - 700)))
    #expect(!shown.live)
    #expect(shown.report.limits.map(\.percent) == [10])
    #expect(shown.fetchedAt == now - 3600)
}

// MARK: - Following the account

@Test func followingAnotherAccountDropsItsInputs() {
    var sources = UsageSources(now: now - 7200)
    let followed = sources.follow(mine, at: now - 600)
    #expect(followed)
    sources.apiAnswered(api([limit(.session, 10)], at: now - 500))
    sources.apiFailed(.rateLimited)
    #expect(sources.api != nil && sources.apiProblem == .rateLimited)
    // The same account again changes nothing.
    let followedAgain = sources.follow(mine, at: now - 400)
    #expect(!followedAgain)
    #expect(sources.lastAccountChange == now - 600 && sources.api != nil)
    let followedOther = sources.follow(theirs, at: now - 300)
    #expect(followedOther)
    #expect(sources.api == nil && sources.apiProblem == nil && sources.lastAccountChange == now - 300)
}

@Test func anApiResultForAnotherAccountIsIgnored() {
    var sources = UsageSources(now: now)
    sources.follow(mine, at: now)
    sources.apiAnswered(api([limit(.session, 10)], at: now, account: theirs))
    #expect(sources.api == nil)
    sources.apiFailed(.offline)
    sources.apiAnswered(api([limit(.session, 10)], at: now))
    #expect(sources.api != nil && sources.apiProblem == nil)
}

@Test func feedFromBeforeTheSwitchIsIgnoredAfterIt() throws {
    var sources = UsageSources(now: now - 7200)
    sources.follow(mine, at: now - 7200)
    sources.feed = feed([limit(.session, 40)], at: now - 30)
    #expect(sources.snapshot(confirmed: nil, local: local, now: now)?.live == true)
    #expect(sources.nextExpiry(now: now) == now - 30 + 600)
    sources.follow(theirs, at: now - 10)
    #expect(sources.snapshot(confirmed: nil, local: profile(theirs, email: "b@example.com"), now: now) == nil)
    #expect(sources.nextExpiry(now: now) == nil)
}

/// A fresh feed entry the API's later window overrules makes nothing live or newer, so the API is not slowed by it.
@Test func aFeedEntryOverruledByALaterApiWindowIsNotLive() throws {
    let reset = now + 3600
    func limit(_ percent: Int, resetsAt: Date) -> UsageLimit {
        UsageLimit(kind: .session, scopeName: nil, percent: percent, severity: .normal, resetsAt: resetsAt, isActive: true, shareOfWeekly: nil)
    }
    let fromApi = api([limit(3, resetsAt: reset)], at: now - 600)
    let fresh = feed([limit(95, resetsAt: reset - 120)], at: now - 5)
    let shown = try #require(build(api: fromApi, feed: fresh))
    #expect(!shown.live)
    #expect(shown.fetchedAt == now - 600)
    #expect(shown.report.limits.map(\.percent) == [3])
    // The same entry in the API's window does take effect.
    let same = try #require(build(api: fromApi, feed: feed([limit(95, resetsAt: reset - 119)], at: now - 5)))
    #expect(same.live && same.fetchedAt == now - 5)

    var sources = UsageSources(now: now - 7200)
    sources.follow(mine, at: now - 7200)
    sources.apiAnswered(fromApi)
    sources.feed = fresh
    #expect(sources.snapshot(confirmed: nil, local: local, now: now)?.live == false)
}

@Test func mergeCountingSaysWhichFeedLimitsTookEffect() {
    let reset = Date(timeIntervalSince1970: 1_792_000_000)
    let apiReport = UsageReport(limits: [
        UsageLimit(kind: .session, scopeName: nil, percent: 3, severity: .normal, resetsAt: reset, isActive: true, shareOfWeekly: nil),
    ], extra: nil)
    let feed = [
        UsageLimit(kind: .session, scopeName: nil, percent: 95, severity: .normal, resetsAt: reset - 18_000, isActive: true, shareOfWeekly: nil),
        UsageLimit(kind: .weeklyAll, scopeName: nil, percent: 20, severity: .normal, resetsAt: nil, isActive: true, shareOfWeekly: nil, position: 1),
    ]
    #expect(LimitMerge.mergeCounting(api: apiReport, feed: feed).applied == [1])
    #expect(LimitMerge.mergeCounting(api: nil, feed: feed).applied == [0, 1])
}
