import Foundation

/// How the menu bar draws the session percentage.
public enum MenuBarTone: Sendable, Equatable {
    case normal
    /// The session is near its limit (`LimitText.isWarning`).
    case warning
    /// The numbers are kept from an earlier poll; muted so they never look current. Wins over `warning`.
    case stale
}

extension Display {
    /// The numbers being shown, current or kept from an earlier poll.
    public var snapshot: Snapshot? {
        switch self {
        case .ready(let snapshot), .stale(let snapshot, _): snapshot
        case .loading, .unavailable: nil
        }
    }

    /// The current session's limit, while there are numbers to show.
    public var sessionLimit: UsageLimit? {
        snapshot?.report.limits.first { $0.kind == .session }
    }

    /// "12%", or a dash when there is no session number.
    public var menuBarText: String {
        sessionLimit.map { "\($0.percent)%" } ?? "–"
    }

    public var menuBarTone: MenuBarTone {
        guard let session = sessionLimit else { return .normal }
        if case .stale = self { return .stale }
        return LimitText.isWarning(session) ? .warning : .normal
    }

    /// What VoiceOver reads for the menu bar item; a kept number is said to be not current.
    public var menuBarAccessibilityLabel: String {
        guard let session = sessionLimit else { return "Gondar" }
        let label = "Gondar, session \(session.percent)% used"
        if case .stale = self { return label + ", not current" }
        return label
    }
}
