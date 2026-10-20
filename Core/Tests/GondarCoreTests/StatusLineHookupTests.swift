import Foundation
import Testing

@testable import GondarCore

private let tool = "/Applications/Gondar.app/Contents/MacOS/gondar-feed"

private func settings(_ json: String) -> Data { Data(json.utf8) }

@Test func wrapsTheCurrentCommand() {
    let hookup = StatusLineHookup.make(settingsJSON: settings(#"{"statusLine": {"type": "command", "command": "npx -y example-statusline", "padding": 0}}"#), tool: tool)
    #expect(hookup == .wrap(
        current: "npx -y example-statusline",
        command: #""/Applications/Gondar.app/Contents/MacOS/gondar-feed" npx -y example-statusline"#
    ))
    // What the person pastes as the JSON value, quotes included.
    #expect(hookup.jsonValue == #""\"/Applications/Gondar.app/Contents/MacOS/gondar-feed\" npx -y example-statusline""#)
}

@Test func commandWithQuotesAndBackslashesIsEscapedForJSON() {
    let hookup = StatusLineHookup.make(settingsJSON: settings(#"{"statusLine": {"command": "sh -c \"echo a\\b\""}}"#), tool: tool)
    #expect(hookup.command == #""/Applications/Gondar.app/Contents/MacOS/gondar-feed" sh -c "echo a\b""#)
    #expect(hookup.jsonValue == #""\"/Applications/Gondar.app/Contents/MacOS/gondar-feed\" sh -c \"echo a\\b\"""#)
}

@Test func alreadyWrappedIsConnected() {
    for command in [
        #""/Applications/Gondar.app/Contents/MacOS/gondar-feed" npx -y example-statusline"#,
        "/Applications/Gondar.app/Contents/MacOS/gondar-feed npx -y example-statusline",
        #"  '/Users/x/Applications/Gondar.app/Contents/MacOS/gondar-feed'"#,
    ] {
        let json = try! JSONSerialization.data(withJSONObject: ["statusLine": ["command": command]])
        #expect(StatusLineHookup.make(settingsJSON: json, tool: tool) == .connected(current: command))
    }
}

@Test func noStatusLineGetsTheToolAlone() {
    for data in [nil, settings("{}"), settings("not json"), settings(#"{"statusLine": {"command": "  "}}"#)] {
        let hookup = StatusLineHookup.make(settingsJSON: data, tool: tool)
        #expect(hookup == .add(command: #""/Applications/Gondar.app/Contents/MacOS/gondar-feed""#))
    }
}

@Test func connectedStatusSaysWhenTheLastReportArrived() throws {
    let now = Date(timeIntervalSince1970: 1_791_990_000)
    #expect(StatusLineHookup.connectedStatus(lastReport: now - 120, now: now) == "Connected — last report 2 min ago")
    #expect(StatusLineHookup.connectedStatus(lastReport: nil, now: now)
        == "Connected — no report yet; it appears after Claude Code's next response")
    let feed = FeedSnapshot(entries: [
        FeedEntry(limit: UsageLimit(kind: .session, scopeName: nil, percent: 1, severity: .normal, resetsAt: nil, isActive: true, shareOfWeekly: nil), receivedAt: now - 300),
        FeedEntry(limit: UsageLimit(kind: .weeklyAll, scopeName: nil, percent: 1, severity: .normal, resetsAt: nil, isActive: true, shareOfWeekly: nil, position: 1), receivedAt: now - 60),
    ])
    #expect(feed.lastReport == now - 60)
    #expect(try StatusLineFeed.parse(Data(#"{"rate_limits": {}, "sessions": {"h": {"api_ms": 1, "seen_at": 1}}}"#.utf8)).lastReport == nil)
}
