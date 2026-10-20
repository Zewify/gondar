import Foundation

/// The change to Claude Code's `statusLine.command` that feeds Gondar, worked out from `~/.claude/settings.json`,
/// which Gondar only ever reads: the person makes the change.
public enum StatusLineHookup: Sendable, Equatable {
    /// The command already runs through Gondar's tool.
    case connected(current: String)
    /// The existing command, and the new one: the tool, quoted, followed by it.
    case wrap(current: String, command: String)
    /// There is no status line command; the new one is the tool alone, which shows nothing but feeds Gondar.
    case add(command: String)

    public static func make(settingsJSON: Data?, tool: String) -> StatusLineHookup {
        let quotedTool = "\"" + tool + "\""
        guard let settingsJSON,
            let object = try? JSONSerialization.jsonObject(with: settingsJSON) as? [String: Any],
            let current = (object["statusLine"] as? [String: Any])?["command"] as? String,
            !current.trimmingCharacters(in: .whitespaces).isEmpty
        else { return .add(command: quotedTool) }
        if runsTool(current) { return .connected(current: current) }
        return .wrap(current: current, command: quotedTool + " " + current)
    }

    /// The new command, or the current one when already connected.
    public var command: String {
        switch self {
        case .connected(let current): current
        case .wrap(_, let command), .add(let command): command
        }
    }

    /// The command as a JSON string, quotes and escapes included: what replaces the old value in settings.json.
    public var jsonValue: String {
        let data = try? JSONSerialization.data(withJSONObject: command, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// Whether the command's first word, quoted or not, is a `gondar-feed`.
    private static func runsTool(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let first: Substring
        if let quote = trimmed.first, quote == "\"" || quote == "'" {
            first = trimmed.dropFirst().prefix { $0 != quote }
        } else {
            first = trimmed.prefix { !$0.isWhitespace }
        }
        return first == "gondar-feed" || first.hasSuffix("/gondar-feed")
    }
}
