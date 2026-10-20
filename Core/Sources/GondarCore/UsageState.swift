import Foundation

public enum Source: Sendable, Equatable {
    case claudeCode, claudeAI
}

public struct Snapshot: Sendable, Equatable {
    public let profile: Profile
    public let plan: String?
    public let report: UsageReport
    public let fetchedAt: Date
    public let source: Source

    public init(profile: Profile, plan: String?, report: UsageReport, fetchedAt: Date, source: Source) {
        self.profile = profile
        self.plan = plan
        self.report = report
        self.fetchedAt = fetchedAt
        self.source = source
    }
}

public enum Problem: Sendable, Equatable {
    case claudeCodeNotSignedIn, keychainUnreadable, tokenExpired, unauthorized, rateLimited, offline, unreadableResponse
    /// The token and `~/.claude.json` have named different accounts three polls in a row.
    case accountSwitchPending
    /// Shown numbers that no poll has replaced for longer than `Display.staleAfter`, with no failure to name.
    case notUpdating

    public var message: String {
        switch self {
        case .claudeCodeNotSignedIn: "Sign in to Claude Code."
        case .keychainUnreadable: "Couldn't read Claude Code's login from the Keychain."
        case .tokenExpired: "Open Claude Code to refresh."
        case .unauthorized: "Claude Code's login was refused. Sign in to Claude Code again."
        case .rateLimited: "Asked too often. Trying again shortly."
        case .offline: "Offline."
        case .unreadableResponse: "Anthropic changed the usage format. An update is needed."
        case .accountSwitchPending: "Waiting for Claude Code to finish switching accounts."
        case .notUpdating: "Not updated for several minutes."
        }
    }

    /// The few words the pop-out shows beside its name while the numbers are stale; `message` is its tooltip.
    public var shortLabel: String {
        switch self {
        case .claudeCodeNotSignedIn: "Signed out"
        case .keychainUnreadable: "Keychain error"
        case .tokenExpired: "Login expired"
        case .unauthorized: "Login refused"
        case .rateLimited: "Rate limited"
        case .offline: "Offline"
        case .unreadableResponse: "Format changed"
        case .accountSwitchPending: "Switching account"
        case .notUpdating: "Not updating"
        }
    }
}

/// Which numbers are which: an account within one organisation. Switching either is a different account to show.
public struct AccountKey: Sendable, Equatable {
    public let accountUUID: String
    public let organizationUUID: String

    public init(accountUUID: String, organizationUUID: String) {
        self.accountUUID = accountUUID
        self.organizationUUID = organizationUUID
    }
}

extension Profile {
    public var accountKey: AccountKey { AccountKey(accountUUID: accountUUID, organizationUUID: organizationUUID) }
}

extension LocalAccount {
    public var key: AccountKey { AccountKey(accountUUID: accountUUID, organizationUUID: organizationUUID) }
}

public enum Display: Sendable, Equatable {
    case loading
    case ready(Snapshot)
    case stale(Snapshot, Problem)
    case unavailable(Problem)
}

/// What the panel shows. Numbers belong to one account in one organisation; a switch of either, or a sign-out, drops them.
public struct UsageState: Sendable, Equatable {
    public private(set) var display: Display = .loading
    public private(set) var account: AccountKey? = nil

    public init() {}

    public mutating func accountChanged(to account: AccountKey?) {
        // A fresh state is .loading with no account; going to nil is a change from it.
        if account == self.account, !(account == nil && display == .loading) { return }
        self.account = account
        display = account == nil ? .unavailable(.claudeCodeNotSignedIn) : .loading
    }

    public mutating func received(_ snapshot: Snapshot) {
        guard let account, snapshot.profile.accountKey == account else { return }
        display = .ready(snapshot)
    }

    public mutating func failed(_ problem: Problem) {
        switch display {
        case .ready(let last), .stale(let last, _):
            display = .stale(last, problem)
        case .loading, .unavailable:
            display = .unavailable(problem)
        }
    }
}

/// Counts polls in a row where the token's profile and `~/.claude.json` name different accounts.
/// A switch half done is waited out; one that never settles (an organisation switch with the same token, say)
/// is reported on the third disagreement, so the numbers stop looking current and backoff applies.
public struct AccountMismatch: Sendable, Equatable {
    public static let tolerated = 2
    public private(set) var count = 0

    public init() {}

    /// Records a disagreement; returns true when it should be reported as `.accountSwitchPending`.
    public mutating func disagreed() -> Bool {
        count += 1
        return count > Self.tolerated
    }

    public mutating func agreed() {
        count = 0
    }
}
