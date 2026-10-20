import Foundation
import Testing

@testable import GondarCore

private let account = AccountKey(accountUUID: "00000000-0000-4000-8000-00000000000a", organizationUUID: "00000000-0000-4000-8000-00000000000b")
private let fetched = Date(timeIntervalSince1970: 1_791_990_000)

private func savedSnapshot() -> Snapshot {
    let limits = [
        UsageLimit(kind: .session, scopeName: nil, percent: 36, severity: .normal,
                   resetsAt: fetched + 3600, isActive: true, shareOfWeekly: nil, position: 0),
        UsageLimit(kind: .weeklyScoped, scopeName: "Fable", percent: 2, severity: .other("warning"),
                   resetsAt: nil, isActive: false, shareOfWeekly: 50, position: 2),
        UsageLimit(kind: .other("monthly_new"), scopeName: nil, percent: 70, severity: .normal,
                   resetsAt: fetched + 86_400, isActive: true, shareOfWeekly: nil, position: 5),
    ]
    let extra = ExtraUsage(used: Money(minor: 1234, currency: "USD", exponent: 2), limit: Money(minor: 0, currency: "USD", exponent: 2))
    return Snapshot(
        profile: Profile(
            accountUUID: account.accountUUID, email: "person@example.com", organizationUUID: account.organizationUUID,
            organizationName: "Example Org", organizationType: "claude_max", rateLimitTier: "default_claude_max_20x", seatTier: nil),
        plan: "Max · Max 20x",
        report: UsageReport(limits: limits, extra: extra),
        fetchedAt: fetched,
        source: .claudeCode,
        live: true
    )
}

@Test func roundTrips() throws {
    let shown = savedSnapshot()
    let data = SavedSnapshot.encode(snapshot: shown, accountKey: account)
    let decoded = try #require(SavedSnapshot.decode(data))
    #expect(decoded.0 == account)
    #expect(decoded.1 == shown.report)
    #expect(decoded.2 == fetched)
}

@Test func containsNoEmailOrToken() throws {
    let data = SavedSnapshot.encode(snapshot: savedSnapshot(), accountKey: account)
    let text = String(decoding: data, as: UTF8.self)
    for absent in ["@", "person", "example.com", "Example Org", "token", "sk-ant", "Max · Max 20x"] {
        #expect(!text.contains(absent), "last.json must not contain \(absent)")
    }
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["account_uuid", "organization_uuid", "fetched_at", "limits", "extra"])
}

@Test func savedSnapshotForOtherAccountIsIgnored() {
    let data = SavedSnapshot.encode(snapshot: savedSnapshot(), accountKey: account)
    let other = AccountKey(accountUUID: account.accountUUID, organizationUUID: "another-organization")
    #expect(SavedSnapshot.restore(saved: data, currentAccount: other) == nil)
    let restored = SavedSnapshot.restore(saved: data, currentAccount: account)
    #expect(restored?.report == savedSnapshot().report)
    #expect(restored?.fetchedAt == fetched)
}

@Test func unreadableSavedSnapshotIsIgnored() {
    #expect(SavedSnapshot.decode(Data("nope".utf8)) == nil)
    #expect(SavedSnapshot.decode(Data(#"{"account_uuid": "a"}"#.utf8)) == nil)
    #expect(SavedSnapshot.restore(saved: Data(), currentAccount: account) == nil)
}

@Test func savedSnapshotWithoutExtraUsage() throws {
    let shown = savedSnapshot()
    let plain = Snapshot(profile: shown.profile, plan: nil, report: UsageReport(limits: shown.report.limits, extra: nil),
                         fetchedAt: fetched, source: .claudeCode)
    let decoded = try #require(SavedSnapshot.decode(SavedSnapshot.encode(snapshot: plain, accountKey: account)))
    #expect(decoded.1.extra == nil)
}
