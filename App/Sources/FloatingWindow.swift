import AppKit
import SwiftUI

/// Owns the one pop-out window: always on top, on every Space and over full-screen apps,
/// with the traffic lights drawn inside Gondar's own dark header.
@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 320, height: 300)
    static let minimumSize = NSSize(width: 230, height: 140)
    static let autosaveName = "GondarWindow"
    /// Set while the window is open, so a relaunch reopens it; quitting leaves it set.
    static let openKey = "floatingWindowOpen"

    static var wasOpen: Bool { UserDefaults.standard.bool(forKey: openKey) }

    private let model: UsageModel
    private let content: @MainActor () -> AnyView
    private var window: NSWindow?
    /// True while the window counts as a viewer; a minimised window does not, so its refresh pauses.
    private var isViewing = false
    /// Set once the app starts quitting: the window is closed on the way out, and that close must not forget it was open.
    /// This relies on applicationShouldTerminate always answering .terminateNow; a cancelled quit would leave it set.
    private var isQuitting = false
    /// True from a first open with no saved frame until the window has been fitted to its rows, once.
    private var needsFit = false

    init(model: UsageModel, content: @escaping @MainActor () -> AnyView) {
        self.model = model
        self.content = content
    }

    /// Opens the window, or brings the open one forward; there is never more than one.
    /// `activate` is false when it reopens at launch, so it appears without taking focus from what the person is doing.
    func show(activate: Bool = true) {
        UserDefaults.standard.set(true, forKey: Self.openKey)
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            if activate {
                window.makeKey()
                NSApp.activate()
            }
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.panel)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: content())
        // The SwiftUI content adds the title bar's height to any minimum it states, and overrides the window's own
        // minSize, so the limit is enforced by windowWillResize instead.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.delegate = self
        // Reopens where it was left; the very first time, it is centred at the default size,
        // then fitted to its rows once they arrive (contentFit). After that the saved frame wins.
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
            needsFit = true
        }
        window.setFrameAutosaveName(Self.autosaveName)
        self.window = window
        isViewing = true
        model.viewerAppeared()
        if activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            window.orderFrontRegardless()
        }
        centreTrafficLights(in: window)
    }

    /// Grows or shrinks a window that had no saved frame so every row shows without scrolling,
    /// capped to its screen's visible frame, keeping it centred; it happens once.
    func contentFit(content: CGFloat, viewport: CGFloat) {
        guard needsFit, let window, let screen = window.screen ?? NSScreen.main else { return }
        needsFit = false
        let visible = screen.visibleFrame
        var frame = window.frame
        let height = min(max(frame.height + (content - viewport).rounded(.up), Self.minimumSize.height), visible.height)
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
        window.center()
    }

    /// AppKit places the traffic lights on the title bar's centre line, which sits above the taller header's.
    /// It lays them out again on resize and focus changes, so every one of those moves them back down.
    private func centreTrafficLights(in window: NSWindow) {
        let centreFromTop = WindowView.headerHeight / 2
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind), let titlebar = button.superview else { continue }
            let y = titlebar.frame.height - centreFromTop - button.frame.height / 2
            if button.frame.origin.y != y { button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y)) }
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, Self.minimumSize.width), height: max(frameSize.height, Self.minimumSize.height))
    }

    func windowDidResize(_ notification: Notification) {
        if let window { centreTrafficLights(in: window) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window { centreTrafficLights(in: window) }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window { centreTrafficLights(in: window) }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if let window { centreTrafficLights(in: window) }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard isViewing else { return }
        isViewing = false
        model.viewerDisappeared()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if let window { centreTrafficLights(in: window) }
        guard !isViewing else { return }
        isViewing = true
        model.viewerAppeared()
    }

    /// Called from the app delegate before anything closes, so the window reopens at the next launch.
    func appWillQuit() {
        isQuitting = true
    }

    func windowWillClose(_ notification: Notification) {
        if !isQuitting { UserDefaults.standard.set(false, forKey: Self.openKey) }
        if isViewing { model.viewerDisappeared() }
        isViewing = false
        window = nil
    }
}

/// Lets the window be dragged by the header: a mouse-down here starts a window drag.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
