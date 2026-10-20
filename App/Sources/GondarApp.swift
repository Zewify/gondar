import SwiftUI

@main
struct GondarApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Gondar")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 320)
                .padding(.vertical, 24)
                .background(Theme.panel)
        } label: {
            Text("–")
        }
        .menuBarExtraStyle(.window)
    }
}
