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
    #expect(abs(try #require(report.limits[0].resetsAt).timeIntervalSince(iso("2026-10-20T03:20:00.073099Z"))) < 0.001)
    #expect(report.limits[2].resetsAt == (try iso("2026-10-26T00:00:00Z")))
    #expect(report.limits.map(\.id) == ["session", "weekly_all", "weekly_scoped:Fable"])
    #expect(report.extra == ExtraUsage(used: Money(minor: 0, currency: "USD", exponent: 2), limit: Money(minor: 0, currency: "USD", exponent: 2)))
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
