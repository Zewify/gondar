import GondarCore
import SwiftUI

/// The menu bar panel: whose usage, one row per limit, then the footer.
struct PanelView: View {
    let model: UsageModel
    let onPopOut: () -> Void
    let loginItem: LoginItem
    let updates: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(model: model)
            LimitList(model: model)
            Divider().overlay(Theme.line)
            PanelFooter(model: model, loginItem: loginItem, updates: updates, onPopOut: onPopOut)
        }
        .frame(width: 340)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .background(PanelWindowObserver(onOpen: model.viewerAppeared, onEscape: { false }))
    }
}
