import GondarCore
import SwiftUI

/// The menu bar panel: whose usage, one row per limit, then the footer.
struct PanelView: View {
    let model: UsageModel
    let onPopOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(model: model, compact: false)
            LimitList(model: model, compact: false)
            Divider().overlay(Theme.line)
            PanelFooter(model: model, onPopOut: onPopOut)
        }
        .frame(width: 340)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .background(PanelWindowObserver(
            onOpen: model.viewerAppeared,
            onClose: model.viewerDisappeared,
            onEscape: { false }
        ))
    }
}
