import Foundation

/// The last numbers shown, kept in `last.json` so a relaunch shows them at once, marked as restored.
/// It holds the account and organisation IDs, the limits and the time of the numbers: never a token, an email,
/// an organisation name or a plan, so nothing personal is written.
public enum SavedSnapshot {
    public static func encode(snapshot: Snapshot, accountKey: AccountKey) -> Data {
        let file = File(
            accountUUID: accountKey.accountUUID,
            organizationUUID: accountKey.organizationUUID,
            fetchedAt: snapshot.fetchedAt.timeIntervalSince1970,
            limits: snapshot.report.limits.map(File.Limit.init),
            extra: snapshot.report.extra.map { File.Extra(used: File.Money($0.used), limit: File.Money($0.limit)) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding plain strings, numbers and booleans cannot fail.
        return (try? encoder.encode(file)) ?? Data()
    }

    /// The account, the numbers and their time, or nil when the file is unreadable.
    public static func decode(_ data: Data) -> (AccountKey, UsageReport, Date)? {
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.fetchedAt.isFinite else { return nil }
        let report = UsageReport(limits: file.limits.map(\.limit), extra: file.extra.map { ExtraUsage(used: $0.used.money, limit: $0.limit.money) })
        return (
            AccountKey(accountUUID: file.accountUUID, organizationUUID: file.organizationUUID),
            report,
            Date(timeIntervalSince1970: file.fetchedAt)
        )
    }

    /// The saved numbers when they belong to `currentAccount`; another account's are never shown.
    public static func restore(saved: Data, currentAccount: AccountKey) -> (report: UsageReport, fetchedAt: Date)? {
        guard let (account, report, fetchedAt) = decode(saved), account == currentAccount else { return nil }
        return (report, fetchedAt)
    }

    private struct File: Codable {
        let accountUUID: String
        let organizationUUID: String
        let fetchedAt: Double
        let limits: [Limit]
        let extra: Extra?

        enum CodingKeys: String, CodingKey {
            case accountUUID = "account_uuid"
            case organizationUUID = "organization_uuid"
            case fetchedAt = "fetched_at"
            case limits, extra
        }

        init(accountUUID: String, organizationUUID: String, fetchedAt: Double, limits: [Limit], extra: Extra?) {
            self.accountUUID = accountUUID
            self.organizationUUID = organizationUUID
            self.fetchedAt = fetchedAt
            self.limits = limits
            self.extra = extra
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(accountUUID, forKey: .accountUUID)
            try container.encode(organizationUUID, forKey: .organizationUUID)
            try container.encode(fetchedAt, forKey: .fetchedAt)
            try container.encode(limits, forKey: .limits)
            try container.encode(extra, forKey: .extra)
        }

        struct Limit: Codable {
            let kind: String
            let scope: String?
            let percent: Int
            let severity: String
            let resetsAt: Double?
            let isActive: Bool
            let share: Int?
            let position: Int

            enum CodingKeys: String, CodingKey {
                case kind, scope, percent, severity, share, position
                case resetsAt = "resets_at"
                case isActive = "is_active"
            }

            init(_ limit: UsageLimit) {
                kind = limit.kind.raw
                scope = limit.scopeName
                percent = limit.percent
                severity = limit.severity.raw
                resetsAt = limit.resetsAt?.timeIntervalSince1970
                isActive = limit.isActive
                share = limit.shareOfWeekly
                position = limit.position
            }

            var limit: UsageLimit {
                UsageLimit(
                    kind: LimitKind(raw: kind), scopeName: scope, percent: percent, severity: Severity(raw: severity),
                    resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)), isActive: isActive, shareOfWeekly: share, position: position
                )
            }
        }

        struct Extra: Codable {
            let used: Money
            let limit: Money
        }

        struct Money: Codable {
            let minor: Int
            let currency: String
            let exponent: Int

            init(_ money: GondarCore.Money) {
                minor = money.minor
                currency = money.currency
                exponent = money.exponent
            }

            var money: GondarCore.Money { GondarCore.Money(minor: minor, currency: currency, exponent: exponent) }
        }
    }
}
