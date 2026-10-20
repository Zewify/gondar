import AppKit
import SwiftUI

/// Observes the window hosting it, reports each time it opens, and gives that window an Escape handler.
/// The menu bar panel uses it; the floating window does not, because its controller reports its own opening.
/// A window-style MenuBarExtra keeps its view alive between openings, so onAppear is not enough;
/// the panel's window becomes key when shown and resigns key when dismissed.
struct PanelWindowObserver: NSViewRepresentable {
    var onOpen: @MainActor () -> Void = {}
    /// Returns true when it used the key; otherwise Escape reaches the panel and dismisses it.
    let onEscape: @MainActor () -> Bool

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onOpen = onOpen
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        var onOpen: (@MainActor () -> Void)?
        var onEscape: (@MainActor () -> Bool)?
        private var tokens: [NSObjectProtocol] = []
        private var keyMonitor: Any?

        /// True from an opening until the window resigns key, so one opening is reported once.
        private var isOpen = false

        isolated deinit {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }

        private func reportOpen() {
            guard !isOpen else { return }
            isOpen = true
            onOpen?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            // Leaving a window (or all windows) while it was key counts as closing.
            isOpen = false
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportOpen() }
            })
            tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isOpen = false }
            })
            // A key monitor sees Escape whatever the panel's focus is, which onKeyPress does not:
            // nothing in the panel holds focus until the user tabs.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self, self.window?.isKeyWindow == true else { return event }
                let used = MainActor.assumeIsolated { self.onEscape?() ?? false }
                return used ? nil : event
            }
            if window.isKeyWindow { reportOpen() }
        }
    }
}
