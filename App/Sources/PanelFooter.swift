import AppKit
import GondarCore
import SwiftUI

/// Settings, Pop out, Refresh and Quit, in PortGlimpse's footer styling,
/// with an update row above them when a newer release exists (never while `UpdateChecker.feed` is nil).
/// The floating window passes no `onPopOut`, which hides Pop out.
/// `compact` matches the narrow window's 12-point inset; the trailing padding plus the buttons' own 8 makes the same visible edge.
struct PanelFooter: View {
    let model: UsageModel
    let loginItem: LoginItem
    @Bindable var updates: UpdateChecker
    var onPopOut: (() -> Void)?
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            if let version = updates.available {
                updateRow(version)
                Divider().overlay(Theme.line)
            }
            row
            .padding(.leading, inset)
            .padding(.trailing, compact ? 4 : 10)
            .padding(.vertical, 10)
        }
        .background(Theme.footer)
    }

    private var inset: CGFloat { compact ? 12 : 18 }

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
        .padding(.leading, inset)
        .padding(.trailing, compact ? 4 : 10)
        .padding(.vertical, 8)
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
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
            if let onPopOut {
                footerButton("Pop out", action: onPopOut)
            }
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
