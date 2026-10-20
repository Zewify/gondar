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
    /// How old a current snapshot may get before it is shown as stale: the backstop in `PollSchedule`.
    public static let staleAfter: Duration = PollSchedule.staleBackstop

    /// What to show at `now`: a ready snapshot older than `staleAfter` is stale, even with no failure to name,
    /// so numbers that stopped updating for any reason never look current. Used by the menu bar and the panel header.
    /// Live numbers last as long as the feed counts as fresh, since the API is asked only every 15 minutes meanwhile.
    public func presented(now: Date) -> Display {
        guard case .ready(let snapshot) = self else { return self }
        let limit = snapshot.live ? LimitMerge.freshness : Double(Self.staleAfter.components.seconds)
        guard now.timeIntervalSince(snapshot.fetchedAt) > limit else { return self }
        return .stale(snapshot.notLive, .notUpdating)
    }

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
