import AppKit
import GondarCore
import SwiftUI

/// Where the numbers come from, then Pop out, Refresh and Quit, in PortGlimpse's footer styling.
struct PanelFooter: View {
    let model: UsageModel
    let onPopOut: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: sourceLine)
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            footerButton("Pop out", action: onPopOut)
            footerButton("Refresh", action: model.refresh)
                .disabled(!model.canRefresh)
                .help(model.canRefresh ? "Check usage now" : "Checked under a minute ago")
            footerButton("Quit") { NSApp.terminate(nil) }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(Theme.footer)
    }

    private var sourceLine: String {
        switch model.state.display.snapshot?.source ?? .claudeCode {
        case .claudeCode: "From Claude Code"
        case .claudeAI: "From claude.ai"
        }
    }

    private func footerButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(FooterButtonStyle())
    }
}

/// PortGlimpse's footer text buttons: muted semibold text, faded while disabled.
private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.muted)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
    }
}
