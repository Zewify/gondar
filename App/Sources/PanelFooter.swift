import AppKit
import GondarCore
import SwiftUI

/// Settings, Pop out, Refresh and Quit, in PortGlimpse's footer styling,
/// with an update row above them when a newer release exists (never while `UpdateChecker.feed` is nil).
struct PanelFooter: View {
    let model: UsageModel
    let loginItem: LoginItem
    @Bindable var updates: UpdateChecker
    let onPopOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let version = updates.available {
                updateRow(version)
                Divider().overlay(Theme.line)
            }
            row
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
        }
        .background(Theme.footer)
    }

    private func updateRow(_ version: AppVersion) -> some View {
        HStack {
            Text(verbatim: "Update available: \(version)")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.amber)
                .lineLimit(1)
            Spacer(minLength: 4)
            if UpdateChecker.installCommand != nil {
                footerButton("Copy install command") { updates.copyInstallCommand() }
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
            // Opened after the menu closes, so the alert is not drawn under it.
            Button("Connect Claude Code's status line…") { DispatchQueue.main.async { StatusLineHookupAlert.show() } }
            if UpdateChecker.feed != nil {
                Toggle("Check for updates", isOn: $updates.isEnabled)
            }
        } label: {
            // A borderless Menu draws its title in the system label colour and ignores foregroundStyle on a plain string;
            // a styled label view is respected.
            Text("Settings")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var row: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 4)
            settingsMenu
            footerButton("Pop out", action: onPopOut)
            footerButton("Refresh", action: model.refresh)
                .disabled(!model.canRefresh)
                .help(model.canRefresh ? "Check usage now" : "Checked under a minute ago")
            footerButton("Quit") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(FooterButtonStyle())
    }
}

/// PortGlimpse's footer text buttons: muted semibold text, faded while disabled.
/// Faded to 0.65, not further: that is 3.5:1 on the footer (6.4:1 enabled), still legible at 13 points on a 1x display.
private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.muted)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.65)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
    }
}

/// Shows the one change to `~/.claude/settings.json` that feeds Gondar from Claude Code's status line, with a Copy button.
/// The file is only read: the person makes the change.
@MainActor
enum StatusLineHookupAlert {
    static let tool = "/Applications/Gondar.app/Contents/MacOS/gondar-feed"
    static let settingsURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")

    static func show() {
        let hookup = StatusLineHookup.make(settingsJSON: try? Data(contentsOf: settingsURL), tool: tool)
        let alert = NSAlert()
        alert.alertStyle = .informational
        switch hookup {
        case .connected:
            alert.messageText = "Claude Code's status line is connected."
            alert.informativeText = "Its command in ~/.claude/settings.json already runs through Gondar's feed, so Gondar shows live numbers while Claude Code runs."
            alert.addButton(withTitle: "OK")
        case .wrap:
            alert.messageText = "Connect Claude Code's status line"
            alert.informativeText = """
                In ~/.claude/settings.json, change only the value of "command" under "statusLine": replace it, quotes included, \
                with the text below. Leave everything else as it is. Your status line looks the same; Gondar reads its usage numbers.
                """
            alert.addButton(withTitle: "Copy")
            alert.addButton(withTitle: "Close")
        case .add:
            alert.messageText = "Connect Claude Code's status line"
            alert.informativeText = """
                ~/.claude/settings.json has no status line command. Add a "statusLine" with "type": "command" and the "command" below. \
                Gondar's feed shows nothing itself; to keep a status line, put its command after the feed's path.
                """
            alert.addButton(withTitle: "Copy")
            alert.addButton(withTitle: "Close")
        }
        alert.accessoryView = commandField(hookup.jsonValue)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if case .connected = hookup { return }
        if response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hookup.jsonValue, forType: .string)
        }
    }

    /// The value in a selectable, wrapping monospaced field, so it can be read in full and copied by hand too.
    private static func commandField(_ text: String) -> NSView {
        let field = NSTextField(wrappingLabelWithString: text)
        field.isSelectable = true
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.preferredMaxLayoutWidth = 360
        field.frame = NSRect(x: 0, y: 0, width: 360, height: field.intrinsicContentSize.height)
        return field
    }
}
