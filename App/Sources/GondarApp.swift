import AppKit
import os
import SwiftUI

@main
struct GondarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model, onPopOut: { delegate.popOut() })
        } label: {
            MenuBarLabel(
                text: delegate.model.menuBarText,
                tone: delegate.model.menuBarTone,
                accessibilityLabel: delegate.model.menuBarAccessibilityLabel
            )
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageModel()
    lazy var window = FloatingWindowController(model: model) { [unowned self] in
        AnyView(WindowView(model: model))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        // It was open when the app last quit: put it back where it was, without taking focus.
        if FloatingWindowController.wasOpen { window.show(activate: false) }
    }

    /// Closing the floating window leaves the app in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        window.appWillQuit()
        return .terminateNow
    }

    /// Opens the window and closes the menu bar panel.
    /// The panel is closed the way a click on its icon closes it: closing or hiding its window directly
    /// leaves MenuBarExtra believing it is still open, and the next click on the icon would do nothing.
    func popOut() {
        // The panel is the key window at click time; taken before the pop-out window becomes key.
        let panelWindow = NSApp.keyWindow
        window.show()
        // If the system already closed the panel when it resigned key, clicking the icon would open it again.
        guard panelWindow?.isVisible == true else { return }
        guard let button = Self.statusItemButton() else {
            Self.logger.error("Couldn't find the status item button to close the panel")
            return
        }
        button.performClick(nil)
    }

    private static let logger = Logger(subsystem: "com.zewify.gondar", category: "panel")

    private static func statusItemButton() -> NSButton? {
        func button(in view: NSView) -> NSButton? {
            if let found = view as? NSButton { return found }
            for child in view.subviews { if let found = button(in: child) { return found } }
            return nil
        }
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let content = window.contentView, let found = button(in: content) { return found }
        }
        return nil
    }
}
