import GondarCore
import SwiftUI

/// The pop-out window's content: the panel's header, rows and footer under a draggable title row.
/// Below 280 points wide the header and rows switch to their compact layout,
/// and the list always scrolls within whatever height the window has.
struct WindowView: View {
    static let compactWidth: CGFloat = 280
    /// The header must stay taller than the title bar: on macOS 26 a scroll view that meets the title bar gets a tinted
    /// band drawn over the header. The traffic lights are moved down to its centre line by FloatingWindowController.
    static let headerHeight: CGFloat = 44

    let model: UsageModel

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < Self.compactWidth
            VStack(spacing: 0) {
                header(compact: compact)
                Divider().overlay(Theme.line)
                ScrollView {
                    VStack(spacing: 0) {
                        PanelHeader(model: model, compact: compact)
                        LimitList(model: model, compact: compact)
                    }
                }
                Divider().overlay(Theme.line)
                PanelFooter(model: model, compact: compact)
            }
        }
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        // The content runs under the transparent title bar so the traffic lights sit in the header's own row.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The traffic lights sit over the leading 78 points; the text ignores clicks so the drag handle gets them.
    private func header(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Text("Gondar")
                .font(Theme.title(compact ? 15 : 16))
                .tracking(-0.5)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .allowsHitTesting(false)
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: Self.headerHeight)
        .background(WindowDragHandle())
    }
}
