import Foundation

public enum LimitKind: Sendable, Equatable {
    case session, weeklyAll, weeklyScoped
    case other(String)

    init(raw: String) {
        switch raw {
        case "session": self = .session
        case "weekly_all": self = .weeklyAll
        case "weekly_scoped": self = .weeklyScoped
        default: self = .other(raw)
        }
    }

    var raw: String {
        switch self {
        case .session: "session"
        case .weeklyAll: "weekly_all"
        case .weeklyScoped: "weekly_scoped"
        case .other(let raw): raw
        }
    }
}

public enum Severity: Sendable, Equatable {
    case normal
    case other(String)

    init(raw: String) {
        self = raw == "normal" ? .normal : .other(raw)
    }
}

public struct UsageLimit: Sendable, Equatable, Identifiable {
    public let kind: LimitKind
    public let scopeName: String?
    public let percent: Int
    public let severity: Severity
    public let resetsAt: Date?
    public let isActive: Bool
    public let shareOfWeekly: Int?
    /// The entry's position in the response's own list, counting entries that could not be read.
    public let position: Int

    /// Identity for SwiftUI: the position, so two entries alike never collide, then the kind and any scope,
    /// so identical responses give identical ids.
    public var id: String {
        let base = scopeName.map { "\(kind.raw):\($0)" } ?? kind.raw
        return "\(position):\(base)"
    }

    public init(
        kind: LimitKind, scopeName: String?, percent: Int, severity: Severity,
        resetsAt: Date?, isActive: Bool, shareOfWeekly: Int?, position: Int = 0
    ) {
        self.kind = kind
        self.scopeName = scopeName
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.isActive = isActive
        self.shareOfWeekly = shareOfWeekly
        self.position = position
    }
}

public struct Money: Sendable, Equatable {
    public let minor: Int
    public let currency: String
    public let exponent: Int

    public init(minor: Int, currency: String, exponent: Int) {
        self.minor = minor
        self.currency = currency
        self.exponent = exponent
    }
}

public struct ExtraUsage: Sendable, Equatable {
    public let used: Money
    public let limit: Money

    public init(used: Money, limit: Money) {
        self.used = used
        self.limit = limit
    }
}

public struct UsageReport: Sendable, Equatable {
    public let limits: [UsageLimit]
    public let extra: ExtraUsage?

    public init(limits: [UsageLimit], extra: ExtraUsage?) {
        self.limits = limits
        self.extra = extra
    }
}

public enum OAuthUsageParser {
    public static func parse(_ data: Data) throws -> UsageReport {
        let wire: WireReport
        do {
            wire = try JSONDecoder().decode(WireReport.self, from: data)
        } catch {
            throw ParseError("The usage response is not in the expected shape")
        }
        let shares = Dictionary(
            wire.weeklyScopedShares.compactMap { $0.value }.map { ($0.limitIndex, $0.allowancePercentOfWeekly) },
            uniquingKeysWith: { first, _ in first }
        )
        // limit_index counts positions in the response's own list, so number the entries before skipping bad ones.
        let limits = wire.limits.enumerated().compactMap { index, entry -> UsageLimit? in
            guard let limit = entry.value else { return nil }
            return UsageLimit(
                kind: LimitKind(raw: limit.kind),
                scopeName: limit.scope?.model?.displayName,
                percent: limit.percent,
                severity: Severity(raw: limit.severity),
                resetsAt: limit.resetsAt,
                isActive: limit.isActive,
                shareOfWeekly: shares[index],
                position: index
            )
        }
        // Entries that are all unreadable mean the format changed: an error, never an empty panel.
        if limits.isEmpty, !wire.limits.isEmpty {
            throw ParseError("No usage limit in the response could be read")
        }
        let extra: ExtraUsage? = wire.spend.flatMap { spend in
            guard spend.enabled else { return nil }
            return ExtraUsage(used: spend.used.money, limit: spend.limit.money)
        }
        return UsageReport(limits: limits, extra: extra)
    }
}

// MARK: - Wire types

private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct WireReport: Decodable {
    let limits: [FailableDecodable<WireLimit>]
    let spend: WireSpend?
    let weeklyScopedShares: [FailableDecodable<WireShare>]

    enum CodingKeys: String, CodingKey {
        case limits, spend
        case weeklyScopedShares = "weekly_scoped_shares"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limits = try container.decode([FailableDecodable<WireLimit>].self, forKey: .limits)
        spend = try? container.decodeIfPresent(WireSpend.self, forKey: .spend)
        weeklyScopedShares = (try? container.decodeIfPresent([FailableDecodable<WireShare>].self, forKey: .weeklyScopedShares)) ?? []
    }
}

private struct WireLimit: Decodable {
    let kind: String
    let percent: Int
    let severity: String
    let resetsAt: Date?
    let scope: Scope?
    let isActive: Bool

    struct Scope: Decodable {
        let model: Model?
        struct Model: Decodable {
            let displayName: String?
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind, percent, severity, scope
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        // Measured as whole numbers; a fraction is rounded rather than dropping the entry. A whole number still decodes.
        let rawPercent = try container.decode(Double.self, forKey: .percent)
        guard rawPercent.isFinite, abs(rawPercent) < 1_000_000 else {
            throw DecodingError.dataCorruptedError(forKey: .percent, in: container, debugDescription: "Not a usable percentage")
        }
        percent = Int(rawPercent.rounded())
        severity = try container.decode(String.self, forKey: .severity)
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope)
        // Missing means active: the bar is drawn muted only when the source says the limit is inactive.
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        if let text = try container.decodeIfPresent(String.self, forKey: .resetsAt) {
            // Both the fractional-second and whole-second forms parse with this style on macOS 14+.
            let parsed = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)
            // The server jitters about a second either side of the boundary (09:39:59.757, 09:40:00.236);
            // rounded to the minute, the clock time never reads a minute early.
            let t = parsed.timeIntervalSinceReferenceDate
            resetsAt = Date(timeIntervalSinceReferenceDate: (t / 60).rounded() * 60)
        } else {
            resetsAt = nil
        }
    }
}

private struct WireShare: Decodable {
    let limitIndex: Int
    let allowancePercentOfWeekly: Int

    enum CodingKeys: String, CodingKey {
        case limitIndex = "limit_index"
        case allowancePercentOfWeekly = "allowance_percent_of_weekly"
    }
}

private struct WireSpend: Decodable {
    let used: WireMoney
    let limit: WireMoney
    let enabled: Bool
}

private struct WireMoney: Decodable {
    let amountMinor: Int
    let currency: String
    let exponent: Int

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency, exponent
    }

    var money: Money { Money(minor: amountMinor, currency: currency, exponent: exponent) }
}
