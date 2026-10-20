import AppKit
import GondarCore
import SwiftUI

/// Where the numbers come from, then Pop out, Refresh and Quit, in PortGlimpse's footer styling.
/// The floating window passes no `onPopOut`, which hides Pop out; when it is too narrow for the source line, the line goes.
/// `compact` matches the narrow window's 12-point inset; the trailing padding plus the buttons' own 8 makes the same visible edge.
struct PanelFooter: View {
    let model: UsageModel
    var onPopOut: (() -> Void)?
    var compact = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showingSource: true)
            row(showingSource: false)
        }
        .padding(.leading, compact ? 12 : 18)
        .padding(.trailing, compact ? 4 : 10)
        .padding(.vertical, 10)
        .background(Theme.footer)
    }

    private func row(showingSource: Bool) -> some View {
        HStack(spacing: 4) {
            if showingSource {
                Text(verbatim: sourceLine)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if let onPopOut {
                footerButton("Pop out", action: onPopOut)
            }
            footerButton("Refresh", action: model.refresh)
                .disabled(!model.canRefresh)
                .help(model.canRefresh ? "Check usage now" : "Checked under a minute ago")
            footerButton("Quit") { NSApp.terminate(nil) }
        }
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
