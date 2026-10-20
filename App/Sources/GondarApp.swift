import AppKit
import os
import SwiftUI

@main
struct GondarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model, onPopOut: { delegate.popOut() }, loginItem: delegate.loginItem, updates: delegate.updates)
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
    let loginItem = LoginItem()
    let updates = UpdateChecker()
    lazy var floatingWindow: FloatingWindowController = FloatingWindowController(model: model, persists: !Self.isDemo) { [unowned self] in
        AnyView(WindowView(model: model) { [unowned self] content, viewport in
            floatingWindow.contentFit(content: content, viewport: viewport)
        })
    }

    /// The Debug-only demo (`-GondarDemo live` or `stale`), which runs beside the installed app under the same bundle ID and defaults.
    private static var isDemo: Bool {
        #if DEBUG
        DemoMode.isEnabled
        #else
        false
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        // The demo opens its window at once and touches nothing shared: no update check, no login item, no saved state.
        if Self.isDemo {
            floatingWindow.show()
            return
        }
        updates.start()
        loginItem.enableOnFirstLaunch()
        // It was open when the app last quit: put it back where it was, without taking focus.
        if FloatingWindowController.wasOpen { floatingWindow.show(activate: false) }
    }

    /// Closing the floating window leaves the app in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        floatingWindow.appWillQuit()
        return .terminateNow
    }

    /// Opens the window and closes the menu bar panel.
    /// The panel is closed the way a click on its icon closes it: closing or hiding its window directly
    /// leaves MenuBarExtra believing it is still open, and the next click on the icon would do nothing.
    func popOut() {
        // The panel is the key window at click time; taken before the pop-out window becomes key.
        let panelWindow = NSApp.keyWindow
        floatingWindow.show()
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
