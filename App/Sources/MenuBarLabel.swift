import AppKit
import GondarCore
import SwiftUI

/// The gauge mark in full colour and the session percentage, drawn into one image: a MenuBarExtra label ignores fonts and colours,
/// and the number needs both, amber near the limit and muted when it is kept from an earlier poll.
@MainActor
enum MenuBarImage {
    private static let tileSize = GaugeMark.tileSize
    private static let gap: CGFloat = 4
    private static let font = NSFont(name: "IBMPlexMono-SemiBold", size: 13) ?? .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    static func image(text: String, tone: MenuBarTone, accessibilityLabel: String) -> NSImage {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let size = NSSize(width: tileSize + gap + ceil(textSize.width), height: tileSize)
        // Drawn on demand, so it stays sharp at the display's scale and the plain number follows the menu bar's appearance.
        let image = NSImage(size: size, flipped: false) { _ in
            if let ctx = NSGraphicsContext.current?.cgContext { GaugeMark.drawMenuBarIcon(in: ctx) }
            let origin = NSPoint(x: tileSize + gap, y: ((tileSize - textSize.height) / 2).rounded())
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: color(for: tone)])
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    private static func color(for tone: MenuBarTone) -> NSColor {
        switch tone {
        case .warning: NSColor(Theme.amber)
        case .stale: NSColor(Theme.muted)
        case .normal:
            // The app is dark only, but the menu bar follows the wallpaper and the system setting.
            NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .aqua ? .labelColor : NSColor(Theme.text)
        }
    }
}

struct MenuBarLabel: View {
    let text: String
    let tone: MenuBarTone
    let accessibilityLabel: String

    var body: some View {
        Image(nsImage: MenuBarImage.image(text: text, tone: tone, accessibilityLabel: accessibilityLabel))
    }
}
