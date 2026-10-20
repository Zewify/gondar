import AppKit
import SwiftUI

/// Observes the window hosting it and gives that window an Escape handler.
/// The menu bar panel reports open and close (the model pairs them) and passes an Escape handler that declines the key.
/// The pop-out window passes only onEscape, because its controller pairs its own viewer calls with show, minimise and close.
/// A window-style MenuBarExtra keeps its view alive between openings, so onAppear is not enough;
/// the panel's window becomes key when shown and resigns key when dismissed.
struct PanelWindowObserver: NSViewRepresentable {
    var onOpen: @MainActor () -> Void = {}
    var onClose: @MainActor () -> Void = {}
    /// The screen the window is on: when it joins a window, each time it is shown, and when it moves to another screen.
    var onScreen: @MainActor (NSScreen) -> Void = { _ in }
    /// Returns true when it used the key; otherwise Escape reaches the panel and dismisses it.
    let onEscape: @MainActor () -> Bool

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onOpen = onOpen
        view.onClose = onClose
        view.onScreen = onScreen
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        var onOpen: (@MainActor () -> Void)?
        var onClose: (@MainActor () -> Void)?
        var onScreen: (@MainActor (NSScreen) -> Void)?
        var onEscape: (@MainActor () -> Bool)?
        private var tokens: [NSObjectProtocol] = []
        private var keyMonitor: Any?

        /// True between an onOpen and its matching onClose, so the two always pair up.
        private var reportedOpen = false

        isolated deinit {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }

        private func reportOpen() {
            guard !reportedOpen else { return }
            reportedOpen = true
            onOpen?()
        }

        private func reportScreen() {
            if let screen = window?.screen { onScreen?(screen) }
        }

        private func reportClose() {
            guard reportedOpen else { return }
            reportedOpen = false
            onClose?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            // Leaving a window (or all windows) while it was key counts as closing.
            reportClose()
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportScreen()
                    self?.reportOpen()
                }
            })
            tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportClose() }
            })
            tokens.append(center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportScreen() }
            })
            // A key monitor sees Escape whatever the panel's focus is, which onKeyPress does not:
            // nothing in the panel holds focus until the user tabs.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self, self.window?.isKeyWindow == true else { return event }
                let used = MainActor.assumeIsolated { self.onEscape?() ?? false }
                return used ? nil : event
            }
            reportScreen()
            if window.isKeyWindow { reportOpen() }
        }
    }
}
