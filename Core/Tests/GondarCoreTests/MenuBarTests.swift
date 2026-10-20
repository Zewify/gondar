import Foundation
import Testing

@testable import GondarCore

private func limit(_ kind: LimitKind, percent: Int, severity: Severity = .normal) -> UsageLimit {
    UsageLimit(kind: kind, scopeName: nil, percent: percent, severity: severity, resetsAt: nil, isActive: true, shareOfWeekly: nil)
}

private func snapshot(_ limits: [UsageLimit]) -> Snapshot {
    Snapshot(
        profile: Profile(
            accountUUID: "a", email: "a@example.com", organizationUUID: "o",
            organizationName: "Org", organizationType: nil, rateLimitTier: nil, seatTier: nil),
        plan: nil,
        report: UsageReport(limits: limits, extra: nil),
        fetchedAt: Date(timeIntervalSince1970: 0),
        source: .claudeCode)
}

@Test func sessionLimitIsTheSessionKind() {
    let display = Display.ready(snapshot([limit(.weeklyAll, percent: 40), limit(.session, percent: 12)]))
    #expect(display.sessionLimit?.percent == 12)
    #expect(Display.stale(snapshot([limit(.session, percent: 7)]), .offline).sessionLimit?.percent == 7)
    #expect(Display.loading.sessionLimit == nil)
    #expect(Display.unavailable(.offline).sessionLimit == nil)
    #expect(Display.ready(snapshot([limit(.weeklyAll, percent: 40)])).sessionLimit == nil)
}

@Test func menuBarTextIsSessionPercentOrDash() {
    #expect(Display.ready(snapshot([limit(.session, percent: 12)])).menuBarText == "12%")
    #expect(Display.loading.menuBarText == "–")
    #expect(Display.unavailable(.tokenExpired).menuBarText == "–")
}

@Test func menuBarToneWarnsAtEightyOrOnSeverity() {
    #expect(Display.ready(snapshot([limit(.session, percent: 79)])).menuBarTone == .normal)
    #expect(Display.ready(snapshot([limit(.session, percent: 80)])).menuBarTone == .warning)
    #expect(Display.ready(snapshot([limit(.session, percent: 5, severity: .other("warning"))])).menuBarTone == .warning)
}

@Test func staleNumbersNeverLookCurrent() {
    #expect(Display.stale(snapshot([limit(.session, percent: 12)]), .offline).menuBarTone == .stale)
    #expect(Display.stale(snapshot([limit(.session, percent: 95)]), .offline).menuBarTone == .stale)
}

@Test func noNumberIsNormalTone() {
    #expect(Display.loading.menuBarTone == .normal)
    #expect(Display.unavailable(.offline).menuBarTone == .normal)
}

@Test func snapshotIsKeptWhileStale() {
    let shown = snapshot([limit(.session, percent: 3)])
    #expect(Display.ready(shown).snapshot == shown)
    #expect(Display.stale(shown, .offline).snapshot == shown)
    #expect(Display.loading.snapshot == nil)
    #expect(Display.unavailable(.offline).snapshot == nil)
}

@Test func menuBarAccessibilitySaysWhenNotCurrent() {
    #expect(Display.ready(snapshot([limit(.session, percent: 12)])).menuBarAccessibilityLabel == "Gondar, session 12% used")
    #expect(Display.stale(snapshot([limit(.session, percent: 12)]), .offline).menuBarAccessibilityLabel == "Gondar, session 12% used, not current")
    #expect(Display.loading.menuBarAccessibilityLabel == "Gondar")
    #expect(Display.unavailable(.offline).menuBarAccessibilityLabel == "Gondar")
}

/// A ready snapshot that has not been replaced for 2 × 120 s + 60 s is shown as stale, so old numbers never look current.
@Test func oldReadyNumbersArePresentedAsStale() {
    let shown = snapshot([limit(.session, percent: 12)])
    let fetched = shown.fetchedAt
    #expect(Display.ready(shown).presented(now: fetched + 300) == .ready(shown))
    #expect(Display.ready(shown).presented(now: fetched + 301) == .stale(shown, .notUpdating))
    #expect(Display.ready(shown).presented(now: fetched + 301).menuBarTone == .stale)
    #expect(Display.ready(shown).presented(now: fetched + 301).menuBarAccessibilityLabel.hasSuffix("not current"))
}

@Test func presentingLeavesOtherStatesAlone() {
    let shown = snapshot([limit(.session, percent: 12)])
    let later = shown.fetchedAt + 10_000
    #expect(Display.stale(shown, .offline).presented(now: later) == .stale(shown, .offline))
    #expect(Display.loading.presented(now: later) == .loading)
    #expect(Display.unavailable(.offline).presented(now: later) == .unavailable(.offline))
}

/// Live numbers are current for as long as the feed is fresh, not only for the API's backstop.
@Test func liveNumbersStayCurrentWhileTheFeedIsFresh() {
    let base = snapshot([limit(.session, percent: 12)])
    let live = Snapshot(profile: base.profile, plan: nil, report: base.report, fetchedAt: base.fetchedAt, source: .claudeCode, live: true)
    #expect(Display.ready(live).presented(now: live.fetchedAt + 599) == .ready(live))
    #expect(Display.ready(live).presented(now: live.fetchedAt + 601) == .stale(live, .notUpdating))
}
