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
    case claudeCodeNotSignedIn, tokenExpired, unauthorized, rateLimited, offline, unreadableResponse

    public var message: String {
        switch self {
        case .claudeCodeNotSignedIn: "Sign in to Claude Code, or to claude.ai below."
        case .tokenExpired: "Open Claude Code to refresh."
        case .unauthorized: "Claude Code's login was refused. Sign in to Claude Code again."
        case .rateLimited: "Asked too often. Trying again shortly."
        case .offline: "Offline."
        case .unreadableResponse: "Anthropic changed the usage format. An update is needed."
        }
    }
}

public enum Display: Sendable, Equatable {
    case loading
    case ready(Snapshot)
    case stale(Snapshot, Problem)
    case unavailable(Problem)
}

/// What the panel shows. Numbers belong to one account; a switch or sign-out drops them.
public struct UsageState: Sendable, Equatable {
    public private(set) var display: Display = .loading
    public private(set) var accountUUID: String? = nil

    public init() {}

    public mutating func accountChanged(to accountUUID: String?) {
        // A fresh state is .loading with no account; going to nil is a change from it.
        if accountUUID == self.accountUUID, !(accountUUID == nil && display == .loading) { return }
        self.accountUUID = accountUUID
        display = accountUUID == nil ? .unavailable(.claudeCodeNotSignedIn) : .loading
    }

    public mutating func received(_ snapshot: Snapshot) {
        guard snapshot.profile.accountUUID == accountUUID else { return }
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
