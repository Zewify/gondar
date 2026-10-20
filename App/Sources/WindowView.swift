import GondarCore
import SwiftUI

/// The pop-out window's content, kept as small as it can be (a design decision): the traffic lights in a draggable strip,
/// then one line per limit (name, percentage, countdown), with no bars, account header, extra usage or footer;
/// those all live in the menu bar panel. A problem shows as one line above the rows, so old numbers never look current.
struct WindowView: View {
    /// The strip the traffic lights sit in. It stays taller than the title bar: on macOS 26 a scroll view that meets the
    /// title bar gets a tinted band drawn over it. The traffic lights are moved to its centre line by FloatingWindowController.
    static let stripHeight: CGFloat = 30
    static let inset: CGFloat = 12
    /// Fits "Weekly · all models", "100%" and "Resetting now", the widest of each, on one line with the gaps and insets
    /// below (measured in the bundled fonts: 112 + 32 + 78 points of text).
    static let minimumWidth: CGFloat = 272

    let model: UsageModel
    /// The rows' full height and the height the scroll view has for them, reported once there are numbers,
    /// so the controller can fit a window that has no saved frame to its content.
    var onContentFit: @MainActor (_ content: CGFloat, _ viewport: CGFloat) -> Void = { _, _ in }

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: Self.stripHeight)
                .background(WindowDragHandle())
            // Scrolls only when the person makes the window shorter than its rows.
            ScrollView {
                content
                    .padding(.horizontal, Self.inset)
                    .padding(.bottom, 10)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0; reportFit() }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewportHeight = $0; reportFit() }
        }
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        // The content runs under the transparent title bar so the traffic lights sit in the strip.
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder private var content: some View {
        switch model.display {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 24)
        case .unavailable(let problem):
            Text(verbatim: problem.message)
                .font(Theme.body(12, .medium))
                .foregroundStyle(Theme.softText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .ready(let snapshot):
            rows(snapshot.report)
        case .stale(let snapshot, let problem):
            VStack(alignment: .leading, spacing: 6) {
                staleLine(snapshot, problem)
                rows(snapshot.report)
            }
        }
    }

    /// The age, muted, and the reason, amber, as one line that wraps when the window is narrow.
    private func staleLine(_ snapshot: Snapshot, _ problem: Problem) -> some View {
        (Text(verbatim: UpdatedText.text(fetchedAt: snapshot.fetchedAt, now: model.now) + " · ").foregroundStyle(Theme.muted)
            + Text(verbatim: problem.message).foregroundStyle(Theme.amber))
            .font(Theme.body(12, .medium))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A grid, so the percentages and countdowns line up in columns.
    private func rows(_ report: UsageReport) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 8) {
            ForEach(report.limits) { limit in
                GridRow {
                    LimitName(limit: limit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LimitPercent(limit: limit)
                        .gridColumnAlignment(.trailing)
                        .padding(.leading, 12)
                    Text(verbatim: ResetText.short(resetsAt: limit.resetsAt, now: model.now))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                        .padding(.leading, 10)
                }
            }
        }
    }

    private func reportFit() {
        guard model.state.display.snapshot != nil, contentHeight > 0, viewportHeight > 0 else { return }
        onContentFit(contentHeight, viewportHeight)
    }
}
