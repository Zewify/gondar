import Foundation
import Testing

@testable import GondarCore

@Test func parsesScrubbedProfile() throws {
    let profile = try Profile.parse(fixture("oauth-profile-2026-10-20.json"))
    #expect(profile.accountUUID == "00000000-0000-4000-8000-00000000000a")
    #expect(profile.email == "test@example.com")
    #expect(profile.organizationUUID == "00000000-0000-4000-8000-00000000000b")
    #expect(profile.organizationName == "Example Org")
    #expect(profile.organizationType == "claude_max")
    #expect(profile.rateLimitTier == "default_claude_max_20x")
    #expect(profile.seatTier == nil)
}

@Test func localProfileFromClaudeJSON() throws {
    let json = #"""
    {"numStartups": 3, "oauthAccount": {"accountUuid": "acc", "emailAddress": "person@example.com", "organizationUuid": "org",
     "organizationName": "Example Org", "organizationType": "claude_max", "organizationRateLimitTier": "default_example",
     "userRateLimitTier": "default_claude_max_20x", "seatTier": null, "displayName": "P"}}
    """#
    let profile = try #require(Profile.parse(claudeJSON: Data(json.utf8)))
    #expect(profile.accountUUID == "acc")
    #expect(profile.organizationUUID == "org")
    #expect(profile.email == "person@example.com")
    #expect(profile.organizationName == "Example Org")
    #expect(profile.organizationType == "claude_max")
    // The organisation's tier is one PlanText does not know; the person's own is.
    #expect(profile.rateLimitTier == "default_claude_max_20x")
    #expect(profile.seatTier == nil)
    #expect(PlanText.label(organizationType: profile.organizationType, rateLimitTier: profile.rateLimitTier) == "Max · Max 20x")
}

@Test func localProfileNeedsBothIDs() {
    #expect(Profile.parse(claudeJSON: Data(#"{"oauthAccount": {"accountUuid": "acc"}}"#.utf8)) == nil)
    #expect(Profile.parse(claudeJSON: Data(#"{}"#.utf8)) == nil)
    let bare = Profile.parse(claudeJSON: Data(#"{"oauthAccount": {"accountUuid": "acc", "organizationUuid": "org"}}"#.utf8))
    #expect(bare?.email == "")
    #expect(bare?.organizationName == "")
    #expect(bare?.rateLimitTier == nil)
}
