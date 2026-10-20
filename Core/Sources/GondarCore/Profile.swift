import Foundation

/// The account and organisation behind the token, from the OAuth profile endpoint.
public struct Profile: Sendable, Equatable {
    public let accountUUID: String
    public let email: String
    public let organizationUUID: String
    public let organizationName: String
    public let organizationType: String?
    public let rateLimitTier: String?
    public let seatTier: String?

    public init(
        accountUUID: String, email: String, organizationUUID: String, organizationName: String,
        organizationType: String?, rateLimitTier: String?, seatTier: String?
    ) {
        self.accountUUID = accountUUID
        self.email = email
        self.organizationUUID = organizationUUID
        self.organizationName = organizationName
        self.organizationType = organizationType
        self.rateLimitTier = rateLimitTier
        self.seatTier = seatTier
    }

    public static func parse(_ data: Data) throws -> Profile {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw ParseError("The profile response is not in the expected shape")
        }
        return Profile(
            accountUUID: wire.account.uuid,
            email: wire.account.email,
            organizationUUID: wire.organization.uuid,
            organizationName: wire.organization.name,
            organizationType: wire.organization.organizationType,
            rateLimitTier: wire.organization.rateLimitTier,
            seatTier: wire.organization.seatTier
        )
    }

    private struct Wire: Decodable {
        let account: Account
        let organization: Organization

        struct Account: Decodable {
            let uuid: String
            let email: String
        }

        struct Organization: Decodable {
            let uuid: String
            let name: String
            let organizationType: String?
            let rateLimitTier: String?
            let seatTier: String?

            enum CodingKeys: String, CodingKey {
                case uuid, name
                case organizationType = "organization_type"
                case rateLimitTier = "rate_limit_tier"
                case seatTier = "seat_tier"
            }
        }
    }
}

extension Profile {
    /// The header fields Claude Code keeps in `~/.claude.json` under `oauthAccount`, shown until the profile endpoint confirms them.
    /// Needs both IDs; anything else missing is left empty. The organisation's rate-limit tier is used when `PlanText` knows it,
    /// otherwise the person's own (`userRateLimitTier`), as a Team seat's Max tier is recorded there.
    public static func parse(claudeJSON: Data) -> Profile? {
        guard let object = try? JSONSerialization.jsonObject(with: claudeJSON) as? [String: Any],
            let account = object["oauthAccount"] as? [String: Any],
            let accountUUID = account["accountUuid"] as? String,
            let organizationUUID = account["organizationUuid"] as? String
        else { return nil }
        let tiers = [account["organizationRateLimitTier"], account["userRateLimitTier"]].compactMap { $0 as? String }
        return Profile(
            accountUUID: accountUUID,
            email: account["emailAddress"] as? String ?? "",
            organizationUUID: organizationUUID,
            organizationName: account["organizationName"] as? String ?? "",
            organizationType: account["organizationType"] as? String,
            rateLimitTier: tiers.first { PlanText.knows(tier: $0) } ?? tiers.first,
            seatTier: account["seatTier"] as? String
        )
    }
}
