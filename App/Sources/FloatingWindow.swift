import AppKit
import GondarCore
import SwiftUI

/// Owns the one pop-out window: always on top, on every Space and over full-screen apps,
/// with the traffic lights drawn in a strip of Gondar's own dark background.
@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    /// The first open's size, before the first numbers fit its height to the rows.
    static let defaultSize = NSSize(width: WindowView.minimumWidth, height: 140)
    /// As narrow as one line per limit allows; as short as the strip and one line.
    static let minimumSize = NSSize(width: WindowView.minimumWidth, height: WindowView.stripHeight + 34)
    static let autosaveName = "GondarWindow"
    /// Set while the window is open, so a relaunch reopens it; quitting leaves it set.
    static let openKey = "floatingWindowOpen"

    static var wasOpen: Bool { UserDefaults.standard.bool(forKey: openKey) }

    private let model: UsageModel
    private let content: @MainActor () -> AnyView
    private var window: NSWindow?
    /// Set once the app starts quitting: the window is closed on the way out, and that close must not forget it was open.
    /// This relies on applicationShouldTerminate always answering .terminateNow; a cancelled quit would leave it set.
    private var isQuitting = false
    /// Set once the window has been fitted to its rows, or once the person has moved or resized it, whichever is first;
    /// until then the first numbers to arrive fit it, even across launches.
    static let fittedKey = "floatingWindowFitted"
    private var isFitted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.fittedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.fittedKey) }
    }
    /// True while the controller places the window itself, so its own moves are not taken for the person's.
    private var isPlacing = false

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
        isPlacing = true
        // Reopens where it was left; the very first time, it is centred at the default size.
        // Until it is fitted (contentFit), the first numbers to arrive fit it to its rows.
        if !window.setFrameUsingName(Self.autosaveName) { window.center() }
        window.setFrameAutosaveName(Self.autosaveName)
        self.window = window
        model.viewerAppeared()
        if activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            window.orderFrontRegardless()
        }
        isPlacing = false
        centreTrafficLights(in: window)
    }

    /// Grows or shrinks the window once so every row shows without scrolling: the top edge stays,
    /// the height is capped to the screen's visible frame, and the window stays inside it.
    func contentFit(content: CGFloat, viewport: CGFloat) {
        guard !isFitted, let window, let screen = window.screen ?? NSScreen.main else { return }
        isFitted = true
        let fitted = WindowFit.frame(
            fitting: Self.rect(window.frame),
            content: content,
            viewport: viewport,
            minimumHeight: Self.minimumSize.height,
            within: Self.rect(screen.visibleFrame)
        )
        isPlacing = true
        window.setFrame(NSRect(x: fitted.x, y: fitted.y, width: fitted.width, height: fitted.height), display: true)
        isPlacing = false
    }

    private static func rect(_ r: NSRect) -> WindowFit.Rect {
        WindowFit.Rect(x: r.origin.x, y: r.origin.y, width: r.width, height: r.height)
    }

    /// The person resizing it: their size wins over the fit.
    func windowWillStartLiveResize(_ notification: Notification) {
        isFitted = true
    }

    /// The person dragging it: their place wins over the fit. The controller's own placing is not counted.
    func windowDidMove(_ notification: Notification) {
        if !isPlacing { isFitted = true }
    }

    /// AppKit places the traffic lights on the title bar's centre line, which sits above the taller strip's.
    /// It lays them out again on resize and focus changes, so every one of those moves them back down.
    private func centreTrafficLights(in window: NSWindow) {
        let centreFromTop = WindowView.stripHeight / 2
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

    /// Coming back from the Dock counts as opening it: poll once, as the model allows.
    func windowDidDeminiaturize(_ notification: Notification) {
        if let window { centreTrafficLights(in: window) }
        model.viewerAppeared()
    }

    /// Called from the app delegate before anything closes, so the window reopens at the next launch.
    func appWillQuit() {
        isQuitting = true
    }

    func windowWillClose(_ notification: Notification) {
        if !isQuitting { UserDefaults.standard.set(false, forKey: Self.openKey) }
        window = nil
    }
}

/// Lets the window be dragged by the strip: a mouse-down here starts a window drag.
/// It also carries the strip's tooltip, since the SwiftUI content above it ignores the pointer.
struct WindowDragHandle: NSViewRepresentable {
    var toolTip: String? = nil

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        if view.toolTip != toolTip { view.toolTip = toolTip }
    }

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
