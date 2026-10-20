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
