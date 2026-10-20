import GondarCore
import SwiftUI

/// The pop-out window's content, kept as small as it can be (a design decision): the traffic lights and the name in a draggable strip,
/// then one line per limit (name, percentage, countdown), with no bars, account header, extra usage or footer;
/// those all live in the menu bar panel. Stale numbers stay, with a short reason and their age in the strip beside the name,
/// so old numbers never look current and status text never pushes the rows out of a window fitted to them.
struct WindowView: View {
    /// The strip the traffic lights and the name sit in. It stays taller than the title bar: on macOS 26 a scroll view that meets the
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
            titleStrip
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

    /// The traffic lights sit over the leading 78 points; the title ignores clicks so the drag handle gets them,
    /// which is also why the stale reason's tooltip is the drag handle's own rather than a SwiftUI `.help`.
    private var titleStrip: some View {
        HStack(spacing: 8) {
            Text("Gondar")
                .font(Theme.title(15))
                .tracking(-0.5)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            if case .stale(let snapshot, let problem) = model.display {
                staleStatus(snapshot, problem)
            }
        }
        .allowsHitTesting(false)
        .padding(.leading, 78)
        .padding(.trailing, Self.inset)
        .frame(height: Self.stripHeight)
        .background(WindowDragHandle(toolTip: staleToolTip))
    }

    /// "Rate limited · 2 min ago" in amber on one line; when the window is too narrow for the age, the reason alone.
    /// It never wraps, so the strip, and the window fitted to the rows, keep their height.
    private func staleStatus(_ snapshot: Snapshot, _ problem: Problem) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(verbatim: StaleText.text(problem, fetchedAt: snapshot.fetchedAt, now: model.now)).fixedSize()
            Text(verbatim: problem.shortLabel).lineLimit(1)
        }
        .font(Theme.body(12, .medium))
        .foregroundStyle(Theme.amber)
        .accessibilityLabel(Text(verbatim: problem.message + " " + UpdatedText.text(fetchedAt: snapshot.fetchedAt, now: model.now) + "."))
    }

    /// The full reason and the age, shown when the pointer rests on the strip while the numbers are stale.
    private var staleToolTip: String? {
        guard case .stale(let snapshot, let problem) = model.display else { return nil }
        return problem.message + " " + UpdatedText.text(fetchedAt: snapshot.fetchedAt, now: model.now) + "."
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
        // Stale numbers stay as they are; the strip says they are old.
        case .ready(let snapshot), .stale(let snapshot, _):
            rows(snapshot.report)
        }
    }

    /// A grid, so the percentages and countdowns line up in columns; a line saying so when the source lists no limits.
    @ViewBuilder private func rows(_ report: UsageReport) -> some View {
        if report.limits.isEmpty {
            Text("No limits reported.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            limitGrid(report.limits)
        }
    }

    private func limitGrid(_ limits: [UsageLimit]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 8) {
            ForEach(limits) { limit in
                // A modifier on a GridRow would turn it into one spanning cell, so VoiceOver gets each limit as one line
                // through the name cell, and the other two cells are hidden from it.
                let countdown = ResetText.short(resetsAt: limit.resetsAt, now: model.now)
                GridRow {
                    LimitName(limit: limit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(LimitText.name(limit)), \(limit.percent)%, \(countdown)"))
                    LimitPercent(limit: limit)
                        .gridColumnAlignment(.trailing)
                        .padding(.leading, 12)
                        .accessibilityHidden(true)
                    Text(verbatim: countdown)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                        .padding(.leading, 10)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func reportFit() {
        guard model.state.display.snapshot != nil, contentHeight > 0, viewportHeight > 0 else { return }
        onContentFit(contentHeight, viewportHeight)
    }
}
