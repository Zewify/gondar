import AppKit
import SwiftUI

@main
struct GondarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Text("Gondar")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 320)
                .padding(.vertical, 24)
                .background(Theme.panel)
        } label: {
            Text(verbatim: delegate.model.menuBarText)
                .monospacedDigit()
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
