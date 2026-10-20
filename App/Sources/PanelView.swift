import GondarCore
import SwiftUI

/// The menu bar panel: whose usage, one row per limit, then the footer.
struct PanelView: View {
    let model: UsageModel
    let onPopOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(model: model, compact: false)
            if let report = model.state.display.snapshot?.report {
                ForEach(report.limits) { limit in
                    Divider().overlay(Theme.line)
                    LimitRow(limit: limit, now: model.now, compact: false)
                }
                if let extra = report.extra {
                    Divider().overlay(Theme.line)
                    ExtraUsageRow(extra: extra, compact: false)
                }
            }
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
