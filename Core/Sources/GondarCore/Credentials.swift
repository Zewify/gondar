import Foundation

/// A response or file that does not have the shape the parsers need.
public struct ParseError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// What Claude Code keeps in its Keychain item, read-only: Gondar never refreshes or rewrites it.
public struct ClaudeCodeCredentials: Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public init(accessToken: String, expiresAt: Date, subscriptionType: String?, rateLimitTier: String?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    /// True when the token has expired or will within 60 seconds.
    public func isExpired(at now: Date) -> Bool {
        now.addingTimeInterval(60) >= expiresAt
    }

    public static func parse(keychainValue: String) throws -> ClaudeCodeCredentials {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: Data(keychainValue.utf8))
        } catch {
            throw ParseError("Claude Code credentials are not in the expected shape")
        }
        let oauth = wire.claudeAiOauth
        return ClaudeCodeCredentials(
            accessToken: oauth.accessToken,
            expiresAt: Date(timeIntervalSince1970: oauth.expiresAt / 1000),
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier
        )
    }

    private struct Wire: Decodable {
        let claudeAiOauth: OAuth
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double
            let subscriptionType: String?
            let rateLimitTier: String?
        }
    }
}

/// The signed-in account as `~/.claude.json` records it, used to notice an account switch.
public struct LocalAccount: Sendable, Equatable {
    public let accountUUID: String
    public let organizationUUID: String

    public init(accountUUID: String, organizationUUID: String) {
        self.accountUUID = accountUUID
        self.organizationUUID = organizationUUID
    }

    public static func parse(claudeJSON: Data) -> LocalAccount? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: claudeJSON) else { return nil }
        return LocalAccount(accountUUID: wire.oauthAccount.accountUuid, organizationUUID: wire.oauthAccount.organizationUuid)
    }

    private struct Wire: Decodable {
        let oauthAccount: Account
        struct Account: Decodable {
            let accountUuid: String
            let organizationUuid: String
        }
    }
}
