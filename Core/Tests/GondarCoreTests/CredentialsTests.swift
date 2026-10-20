import Foundation
import Testing

@testable import GondarCore

private let keychainJSON = """
{"claudeAiOauth":{"accessToken":"tok","refreshToken":"ref","expiresAt":1792476437162,
"scopes":["user:inference"],"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}
"""

@Test func parsesCredentials() throws {
    let credentials = try ClaudeCodeCredentials.parse(keychainValue: keychainJSON)
    #expect(credentials.accessToken == "tok")
    #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1792476437.162))
    #expect(credentials.subscriptionType == "max")
    #expect(credentials.rateLimitTier == "default_claude_max_20x")
}

@Test func credentialsExpireSixtySecondsEarly() throws {
    let credentials = try ClaudeCodeCredentials.parse(keychainValue: keychainJSON)
    #expect(credentials.isExpired(at: credentials.expiresAt.addingTimeInterval(-59)))
    #expect(!credentials.isExpired(at: credentials.expiresAt.addingTimeInterval(-61)))
}

@Test func credentialsWithoutAccessTokenThrow() {
    let json = #"{"claudeAiOauth":{"expiresAt":1792476437162}}"#
    #expect(throws: (any Error).self) { try ClaudeCodeCredentials.parse(keychainValue: json) }
}

@Test func parsesLocalAccount() {
    let json = #"{"oauthAccount":{"accountUuid":"a","organizationUuid":"b"}}"#
    #expect(LocalAccount.parse(claudeJSON: Data(json.utf8)) == LocalAccount(accountUUID: "a", organizationUUID: "b"))
    #expect(LocalAccount.parse(claudeJSON: Data("{}".utf8)) == nil)
}
