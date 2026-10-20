import Foundation
import Testing

@testable import GondarCore

private func key(_ account: String, org: String = "org") -> AccountKey {
    AccountKey(accountUUID: account, organizationUUID: org)
}

private func snap(account: String, org: String = "org") -> Snapshot {
    Snapshot(
        profile: Profile(
            accountUUID: account, email: "\(account)@example.com", organizationUUID: org,
            organizationName: "Org", organizationType: nil, rateLimitTier: nil, seatTier: nil),
        plan: "Max",
        report: UsageReport(limits: [], extra: nil),
        fetchedAt: Date(timeIntervalSince1970: 1_000),
        source: .claudeCode)
}

@Test func startsLoadingForNewAccount() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    #expect(state.display == .loading)
    #expect(state.account == key("a"))
}

@Test func showsSnapshotForCurrentAccount() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.received(snap(account: "a"))
    #expect(state.display == .ready(snap(account: "a")))
}

@Test func dropsSnapshotForPreviousAccount() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.accountChanged(to: key("b"))
    state.received(snap(account: "a"))
    #expect(state.display == .loading)
}

@Test func switchingClearsOldNumbers() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.received(snap(account: "a"))
    state.accountChanged(to: key("b"))
    #expect(state.display == .loading)
}

@Test func sameAccountKeepsNumbers() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.received(snap(account: "a"))
    state.accountChanged(to: key("a"))
    #expect(state.display == .ready(snap(account: "a")))
}

@Test func signedOutIsUnavailable() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.received(snap(account: "a"))
    state.accountChanged(to: nil)
    #expect(state.display == .unavailable(.claudeCodeNotSignedIn))
    state.failed(.offline)
    #expect(state.display == .unavailable(.offline))
}

@Test func staleKeepsLastSnapshot() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
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
    #expect(Problem.claudeCodeNotSignedIn.message == "Sign in to Claude Code.")
    #expect(Problem.tokenExpired.message == "Open Claude Code to refresh.")
    #expect(Problem.unauthorized.message == "Claude Code's login was refused. Sign in to Claude Code again.")
    #expect(Problem.rateLimited.message == "Asked too often. Trying again shortly.")
    #expect(Problem.offline.message == "Offline.")
    #expect(Problem.unreadableResponse.message == "Anthropic changed the usage format. An update is needed.")
    #expect(Problem.keychainUnreadable.message == "Couldn't read Claude Code's login from the Keychain.")
    #expect(Problem.accountSwitchPending.message == "Waiting for Claude Code to finish switching accounts.")
    #expect(Problem.notUpdating.message == "Not updated for several minutes.")
}

/// Short enough to sit beside the pop-out's name (the longest, "Switching account", is about 100 points in Figtree 12).
@Test func problemShortLabels() {
    #expect(Problem.claudeCodeNotSignedIn.shortLabel == "Signed out")
    #expect(Problem.keychainUnreadable.shortLabel == "Keychain error")
    #expect(Problem.tokenExpired.shortLabel == "Login expired")
    #expect(Problem.unauthorized.shortLabel == "Login refused")
    #expect(Problem.rateLimited.shortLabel == "Rate limited")
    #expect(Problem.offline.shortLabel == "Offline")
    #expect(Problem.unreadableResponse.shortLabel == "Format changed")
    #expect(Problem.accountSwitchPending.shortLabel == "Switching account")
    #expect(Problem.notUpdating.shortLabel == "Not updating")
}

@Test func switchingAwayFromStaleDropsOldNumbers() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.received(snap(account: "a"))
    state.failed(.offline)
    state.accountChanged(to: key("b"))
    #expect(state.display == .loading)
    state.failed(.offline)
    #expect(state.display == .unavailable(.offline))
}

@Test func recoversFromStale() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.received(snap(account: "a"))
    state.failed(.offline)
    var newer = snap(account: "a")
    newer = Snapshot(profile: newer.profile, plan: "Pro", report: newer.report, fetchedAt: Date(timeIntervalSince1970: 2_000), source: .claudeAI)
    state.received(newer)
    #expect(state.display == .ready(newer))
}

@Test func recoversFromUnavailable() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.failed(.unauthorized)
    #expect(state.display == .unavailable(.unauthorized))
    state.received(snap(account: "a"))
    #expect(state.display == .ready(snap(account: "a")))
}

@Test func signedOutIgnoresSnapshots() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
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

@Test func organisationOnlySwitchDropsNumbers() {
    var state = UsageState()
    state.accountChanged(to: key("a", org: "one"))
    state.received(snap(account: "a", org: "one"))
    state.accountChanged(to: key("a", org: "two"))
    #expect(state.display == .loading)
    #expect(state.account == key("a", org: "two"))
}

@Test func ignoresSnapshotForSameAccountInAnotherOrganisation() {
    var state = UsageState()
    state.accountChanged(to: key("a", org: "two"))
    state.received(snap(account: "a", org: "one"))
    #expect(state.display == .loading)
    state.received(snap(account: "a", org: "two"))
    #expect(state.display == .ready(snap(account: "a", org: "two")))
}

@Test func accountKeysFromProfileAndAccountFile() {
    let profile = snap(account: "a", org: "one").profile
    #expect(profile.accountKey == key("a", org: "one"))
    #expect(LocalAccount(accountUUID: "a", organizationUUID: "one").key == key("a", org: "one"))
}

@Test func restoredNumbersAreStaleUntilAResult() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.restore(snap(account: "a"))
    #expect(state.display == .stale(snap(account: "a"), .restored))
    state.received(snap(account: "a"))
    #expect(state.display == .ready(snap(account: "a")))
}

@Test func restoredNumbersOfAnotherAccountAreIgnored() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.restore(snap(account: "b"))
    #expect(state.display == .loading)
}

@Test func restoringNeverReplacesNumbersAlreadyShown() {
    var state = UsageState()
    state.accountChanged(to: key("a"))
    state.received(snap(account: "a"))
    let older = Snapshot(profile: snap(account: "a").profile, plan: nil, report: UsageReport(limits: [], extra: nil),
                         fetchedAt: Date(timeIntervalSince1970: 1), source: .claudeCode)
    state.restore(older)
    #expect(state.display == .ready(snap(account: "a")))
}

@Test func restoredMessage() {
    #expect(Problem.restored.message == "Last numbers from before Gondar restarted.")
    #expect(Problem.restored.shortLabel == "Restored")
}
