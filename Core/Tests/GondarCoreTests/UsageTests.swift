import Foundation
import Testing

@testable import GondarCore

@Test func parsesMeasuredUsage() throws {
    let report = try OAuthUsageParser.parse(fixture("oauth-usage-2026-10-20.json"))
    #expect(report.limits.map(\.kind) == [.session, .weeklyAll, .weeklyScoped])
    #expect(report.limits.map(\.percent) == [13, 8, 0])
    #expect(report.limits[2].scopeName == "Fable")
    #expect(report.limits[2].shareOfWeekly == 50)
    #expect(report.limits[0].isActive && !report.limits[1].isActive)
    #expect(report.limits[0].resetsAt == (try iso("2026-10-20T03:20:00Z")))
    #expect(report.limits[2].resetsAt == (try iso("2026-10-26T00:00:00Z")))
    #expect(report.limits.map(\.id) == ["0:session", "1:weekly_all", "2:weekly_scoped:Fable"])
    #expect(report.extra == ExtraUsage(used: Money(minor: 0, currency: "USD", exponent: 2), limit: Money(minor: 0, currency: "USD", exponent: 2)))
}

/// The server's reset times jitter about a second either side of the boundary; the clock time must not read a minute early.
@Test func resetClockTimeIsRoundedToTheMinute() throws {
    func reset(_ text: String) throws -> Date? {
        let json = #"{"limits":[{"kind":"session","percent":1,"severity":"normal","resets_at":"\#(text)","scope":null,"is_active":true}]}"#
        return try OAuthUsageParser.parse(Data(json.utf8)).limits.first?.resetsAt
    }
    #expect(try reset("2026-10-25T23:59:59.757411+00:00") == (try iso("2026-10-26T00:00:00Z")))
    #expect(try reset("2026-10-20T09:40:00.236072+00:00") == (try iso("2026-10-20T09:40:00Z")))
}

@Test func keepsUnknownKindAndSeverity() throws {
    let json = #"{"limits":[{"kind":"daily_new","group":"x","percent":5,"severity":"critical","resets_at":null,"scope":null,"is_active":true}]}"#
    let report = try OAuthUsageParser.parse(Data(json.utf8))
    #expect(report.limits.count == 1)
    #expect(report.limits[0].kind == .other("daily_new"))
    #expect(report.limits[0].severity == .other("critical"))
    #expect(report.limits[0].resetsAt == nil)
}

@Test func skipsMalformedEntryKeepsTheRest() throws {
    let json = """
    {"limits":[
      {"kind":"session","percent":1,"severity":"normal","resets_at":null,"scope":null,"is_active":true},
      {"kind":"weekly_all","severity":"normal","resets_at":null,"scope":null,"is_active":false},
      {"kind":"weekly_all","percent":2,"severity":"normal","resets_at":null,"scope":null,"is_active":false}
    ]}
    """
    let report = try OAuthUsageParser.parse(Data(json.utf8))
    #expect(report.limits.map(\.percent) == [1, 2])
}

@Test func keepsPercentOver100() throws {
    let json = #"{"limits":[{"kind":"session","percent":130,"severity":"normal","resets_at":null,"scope":null,"is_active":true}]}"#
    let report = try OAuthUsageParser.parse(Data(json.utf8))
    #expect(report.limits[0].percent == 130)
}

@Test func noLimitsKeyThrows() {
    #expect(throws: (any Error).self) { try OAuthUsageParser.parse(Data("{}".utf8)) }
}

@Test func extraIsNilWhenSpendDisabled() throws {
    let json = """
    {"limits":[],"spend":{"used":{"amount_minor":5,"currency":"USD","exponent":2},
    "limit":{"amount_minor":10,"currency":"USD","exponent":2},"enabled":false}}
    """
    let report = try OAuthUsageParser.parse(Data(json.utf8))
    #expect(report.extra == nil)
}

/// A fractional percentage must not empty the panel: it is rounded to the nearest whole number.
@Test func roundsAFractionalPercent() throws {
    let json = """
    {"limits":[
      {"kind":"session","percent":12.5,"severity":"normal","resets_at":null,"scope":null,"is_active":true},
      {"kind":"weekly_all","percent":7.4,"severity":"normal","resets_at":null,"scope":null,"is_active":true},
      {"kind":"weekly_scoped","percent":3,"severity":"normal","resets_at":null,"scope":null,"is_active":true}
    ]}
    """
    let report = try OAuthUsageParser.parse(Data(json.utf8))
    #expect(report.limits.map(\.percent) == [13, 7, 3])
}

@Test func missingIsActiveCountsAsActive() throws {
    let json = #"{"limits":[{"kind":"session","percent":4,"severity":"normal","resets_at":null,"scope":null}]}"#
    let report = try OAuthUsageParser.parse(Data(json.utf8))
    #expect(report.limits.count == 1)
    #expect(report.limits[0].isActive)
}

/// Entries that are all unreadable mean the format changed; that must show as an error, not as an empty panel.
@Test func throwsWhenNoEntryCanBeRead() {
    let json = #"{"limits":[{"kind":"session","percent":"lots","severity":"normal"},{"percent":1}]}"#
    #expect(throws: ParseError.self) { try OAuthUsageParser.parse(Data(json.utf8)) }
}

@Test func anEmptyListIsNotAnError() throws {
    #expect(try OAuthUsageParser.parse(Data(#"{"limits":[]}"#.utf8)).limits.isEmpty)
}

/// Two entries with the same kind and scope, or two unknown kinds alike, still get distinct ids;
/// the same response gives the same ids every time.
@Test func idsAreUniqueAndStable() throws {
    let json = """
    {"limits":[
      {"kind":"weekly_scoped","percent":1,"severity":"normal","resets_at":null,"scope":{"model":{"display_name":"Fable"}},"is_active":true},
      {"kind":"weekly_scoped","percent":2,"severity":"normal","resets_at":null,"scope":{"model":{"display_name":"Fable"}},"is_active":true},
      {"kind":"mystery","percent":3,"severity":"normal","resets_at":null,"scope":null,"is_active":true},
      {"kind":"mystery","percent":4,"severity":"normal","resets_at":null,"scope":null,"is_active":true}
    ]}
    """
    let ids = try OAuthUsageParser.parse(Data(json.utf8)).limits.map(\.id)
    #expect(Set(ids).count == 4)
    #expect(try OAuthUsageParser.parse(Data(json.utf8)).limits.map(\.id) == ids)
}
