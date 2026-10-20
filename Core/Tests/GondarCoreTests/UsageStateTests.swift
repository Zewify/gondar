import Foundation
import Testing

@testable import GondarCore

private func snap(account: String) -> Snapshot {
    Snapshot(
        profile: Profile(
            accountUUID: account, email: "\(account)@example.com", organizationUUID: "org",
            organizationName: "Org", organizationType: nil, rateLimitTier: nil, seatTier: nil),
        plan: "Max",
        report: UsageReport(limits: [], extra: nil),
        fetchedAt: Date(timeIntervalSince1970: 1_000),
        source: .claudeCode)
}

@Test func startsLoadingForNewAccount() {
    var state = UsageState()
    state.accountChanged(to: "a")
    #expect(state.display == .loading)
    #expect(state.accountUUID == "a")
}

@Test func showsSnapshotForCurrentAccount() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.received(snap(account: "a"))
    #expect(state.display == .ready(snap(account: "a")))
}

@Test func dropsSnapshotForPreviousAccount() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.accountChanged(to: "b")
    state.received(snap(account: "a"))
    #expect(state.display == .loading)
}

@Test func switchingClearsOldNumbers() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.received(snap(account: "a"))
    state.accountChanged(to: "b")
    #expect(state.display == .loading)
}

@Test func sameAccountKeepsNumbers() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.received(snap(account: "a"))
    state.accountChanged(to: "a")
    #expect(state.display == .ready(snap(account: "a")))
}

@Test func signedOutIsUnavailable() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.received(snap(account: "a"))
    state.accountChanged(to: nil)
    #expect(state.display == .unavailable(.claudeCodeNotSignedIn))
    state.failed(.offline)
    #expect(state.display == .unavailable(.offline))
}

@Test func staleKeepsLastSnapshot() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.received(snap(account: "a"))
    state.failed(.offline)
    #expect(state.display == .stale(snap(account: "a"), .offline))
    state.failed(.tokenExpired)
    #expect(state.display == .stale(snap(account: "a"), .tokenExpired))
}

@Test func failureWithoutSnapshotIsUnavailable() {
    var state = UsageState()
    state.failed(.unauthorized)
    #expect(state.display == .unavailable(.unauthorized))
}

@Test func problemMessages() {
    #expect(Problem.claudeCodeNotSignedIn.message == "Sign in to Claude Code, or to claude.ai below.")
    #expect(Problem.tokenExpired.message == "Open Claude Code to refresh.")
    #expect(Problem.unauthorized.message == "Claude Code's login was refused. Sign in to Claude Code again.")
    #expect(Problem.rateLimited.message == "Asked too often. Trying again shortly.")
    #expect(Problem.offline.message == "Offline.")
    #expect(Problem.unreadableResponse.message == "Anthropic changed the usage format. An update is needed.")
}

@Test func switchingAwayFromStaleDropsOldNumbers() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.received(snap(account: "a"))
    state.failed(.offline)
    state.accountChanged(to: "b")
    #expect(state.display == .loading)
    state.failed(.offline)
    #expect(state.display == .unavailable(.offline))
}

@Test func recoversFromStale() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.received(snap(account: "a"))
    state.failed(.offline)
    var newer = snap(account: "a")
    newer = Snapshot(profile: newer.profile, plan: "Pro", report: newer.report, fetchedAt: Date(timeIntervalSince1970: 2_000), source: .claudeAI)
    state.received(newer)
    #expect(state.display == .ready(newer))
}

@Test func recoversFromUnavailable() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.failed(.unauthorized)
    #expect(state.display == .unavailable(.unauthorized))
    state.received(snap(account: "a"))
    #expect(state.display == .ready(snap(account: "a")))
}

@Test func signedOutIgnoresSnapshots() {
    var state = UsageState()
    state.accountChanged(to: "a")
    state.accountChanged(to: nil)
    state.received(snap(account: "a"))
    #expect(state.display == .unavailable(.claudeCodeNotSignedIn))
}

@Test func freshStateSignedOutIsUnavailable() {
    var state = UsageState()
    state.accountChanged(to: nil)
    #expect(state.display == .unavailable(.claudeCodeNotSignedIn))
}

@Test func repeatedSignedOutKeepsLaterProblem() {
    var state = UsageState()
    state.accountChanged(to: nil)
    state.failed(.offline)
    state.accountChanged(to: nil)
    #expect(state.display == .unavailable(.offline))
}
