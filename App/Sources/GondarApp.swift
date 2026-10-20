import AppKit
import SwiftUI

@main
struct GondarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            // Task 7 opens the floating window here.
            PanelView(model: delegate.model, onPopOut: {})
        } label: {
            MenuBarLabel(text: delegate.model.menuBarText, tone: delegate.model.menuBarTone)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}
