import Foundation
import Testing

@testable import GondarCore

private func limit(
    _ kind: LimitKind, scope: String? = nil, percent: Int = 10, severity: Severity = .normal
) -> UsageLimit {
    UsageLimit(kind: kind, scopeName: scope, percent: percent, severity: severity, resetsAt: nil, isActive: true, shareOfWeekly: nil)
}

private let newYork = TimeZone(identifier: "America/New_York")!
private let english = Locale(identifier: "en_US")
private var newYorkCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = newYork
    calendar.locale = english
    return calendar
}

private func utc(_ text: String) -> Date {
    try! Date.ISO8601FormatStyle().parse(text)
}

@Test func namesEachKind() {
    #expect(LimitText.name(limit(.session)) == "Current session")
    #expect(LimitText.name(limit(.weeklyAll)) == "Weekly · all models")
    #expect(LimitText.name(limit(.weeklyScoped, scope: "Fable")) == "Weekly · Fable")
    #expect(LimitText.name(limit(.weeklyScoped)) == "Weekly · one model")
    #expect(LimitText.name(limit(.other("daily_new"))) == "Daily new")
}

@Test func warnsOnSeverityOrEightyPercent() {
    #expect(!LimitText.isWarning(limit(.session, percent: 79)))
    #expect(LimitText.isWarning(limit(.session, percent: 80)))
    #expect(LimitText.isWarning(limit(.session, percent: 10, severity: .other("high"))))
}

@Test func levelsByPercentage() {
    #expect(LimitText.level(limit(.session, percent: 0)) == .low)
    #expect(LimitText.level(limit(.session, percent: 49)) == .low)
    #expect(LimitText.level(limit(.session, percent: 50)) == .medium)
    #expect(LimitText.level(limit(.session, percent: 79)) == .medium)
    #expect(LimitText.level(limit(.session, percent: 80)) == .high)
    #expect(LimitText.level(limit(.session, percent: 130)) == .high)
}

@Test func levelIsHighWheneverSeverityIsNotNormal() {
    #expect(LimitText.level(limit(.session, percent: 10, severity: .other("high"))) == .high)
}

@Test func levelIgnoresWhetherTheLimitIsActive() {
    let inactive = UsageLimit(
        kind: .weeklyAll, scopeName: nil, percent: 60, severity: .normal, resetsAt: nil, isActive: false, shareOfWeekly: nil
    )
    #expect(LimitText.level(inactive) == .medium)
}

@Test func clampsBar() {
    #expect(LimitText.barFraction(limit(.session, percent: 130)) == 1.0)
    #expect(LimitText.barFraction(limit(.session, percent: -5)) == 0.0)
    #expect(LimitText.barFraction(limit(.session, percent: 12)) == 0.12)
}

@Test func countsDown() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(ResetText.countdown(to: now + 30, now: now) == "under 1 m")
    #expect(ResetText.countdown(to: now + 36 * 60 + 59, now: now) == "36 m")
    #expect(ResetText.countdown(to: now + 96 * 60, now: now) == "1 h 36 m")
    #expect(ResetText.countdown(to: now + (5 * 24 + 3) * 3600 + 20 * 60, now: now) == "5 d 3 h")
}

@Test func missingResetReadsNoResetTime() {
    #expect(ResetText.full(resetsAt: nil, now: Date(), calendar: newYorkCalendar, locale: english) == "No reset time")
}

@Test func pastResetReadsResettingNow() {
    let now = utc("2026-10-20T01:44:00Z")
    #expect(ResetText.full(resetsAt: now - 5, now: now, calendar: newYorkCalendar, locale: english) == "Resetting now")
}

// Foundation (macOS 26, en_US) puts U+202F NARROW NO-BREAK SPACE before AM/PM.
@Test func fullTextToday() {
    let text = ResetText.full(resetsAt: utc("2026-10-20T03:20:00Z"), now: utc("2026-10-20T01:44:00Z"), calendar: newYorkCalendar, locale: english)
    #expect(text == "Resets in 1 h 36 m · 11:20\u{202F}PM")
}

@Test func fullTextOtherDay() {
    let text = ResetText.full(resetsAt: utc("2026-10-26T00:00:00Z"), now: utc("2026-10-20T01:44:00Z"), calendar: newYorkCalendar, locale: english)
    #expect(text == "Resets in 5 d 22 h · Sun, Oct 25, 8:00\u{202F}PM")
}

@Test func planLabel() {
    #expect(PlanText.label(organizationType: "claude_team", rateLimitTier: nil) == "Team")
    #expect(PlanText.label(organizationType: nil, rateLimitTier: nil) == nil)
    #expect(PlanText.label(organizationType: "claude_pro", rateLimitTier: "x") == "Pro")
    #expect(PlanText.label(organizationType: "claude_max", rateLimitTier: "default_claude_max_20x") == "Max · Max 20x")
    #expect(PlanText.label(organizationType: nil, rateLimitTier: "default_claude_max_5x") == "Max 5x")
}

@Test func updatedText() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(UpdatedText.text(fetchedAt: now - 10, now: now) == "Updated just now")
    #expect(UpdatedText.text(fetchedAt: now - 61, now: now) == "Updated 1 min ago")
    #expect(UpdatedText.text(fetchedAt: now - 5 * 60, now: now) == "Updated 5 min ago")
    #expect(UpdatedText.text(fetchedAt: now - 7300, now: now) == "Updated 2 h ago")
}

/// The pop-out's title strip: a short reason and the age, on one line beside the name.
@Test func staleText() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(StaleText.text(.rateLimited, fetchedAt: now - 2 * 60, now: now) == "Rate limited · 2 min ago")
    #expect(StaleText.text(.offline, fetchedAt: now - 5 * 60, now: now) == "Offline · 5 min ago")
    #expect(StaleText.text(.tokenExpired, fetchedAt: now - 3 * 60, now: now) == "Login expired · 3 min ago")
    #expect(StaleText.text(.notUpdating, fetchedAt: now - 10, now: now) == "Not updating · just now")
    #expect(StaleText.text(.unauthorized, fetchedAt: now - 7300, now: now) == "Login refused · 2 h ago")
}

@Test func moneyText() {
    let text = MoneyText.text(Money(minor: 1234, currency: "USD", exponent: 2), locale: english)
    #expect(text == "$12.34")
}

@Test func extraUsageTextAgainstACap() {
    let extra = ExtraUsage(used: Money(minor: 1234, currency: "USD", exponent: 2), limit: Money(minor: 5000, currency: "USD", exponent: 2))
    #expect(MoneyText.extraUsage(extra, locale: english) == .spendOfLimit(used: "$12.34", limit: "$50.00"))
}

@Test func extraUsageTextWithoutACap() {
    let extra = ExtraUsage(used: Money(minor: 0, currency: "USD", exponent: 2), limit: Money(minor: 0, currency: "USD", exponent: 2))
    #expect(MoneyText.extraUsage(extra, locale: english) == .spent("$0.00"))
}

/// The narrow window's countdown: a passed reset never reads "under 1 m".
@Test func shortResetText() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(ResetText.short(resetsAt: nil, now: now) == "No reset time")
    #expect(ResetText.short(resetsAt: now - 5, now: now) == "Resetting now")
    #expect(ResetText.short(resetsAt: now, now: now) == "Resetting now")
    #expect(ResetText.short(resetsAt: now + 30, now: now) == "under 1 m")
    #expect(ResetText.short(resetsAt: now + 96 * 60, now: now) == "1 h 36 m")
}
