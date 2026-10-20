import AppKit
import GondarCore
import SwiftUI

/// The mark and the session percentage, drawn into one image: a MenuBarExtra label ignores fonts and colours,
/// and the number needs both, amber near the limit and muted when it is kept from an earlier poll.
@MainActor
enum MenuBarImage {
    /// Menu bar icons are 18 points tall.
    private static let tileSize: CGFloat = 18
    private static let gap: CGFloat = 4
    private static let font = NSFont(name: "IBMPlexMono-SemiBold", size: 13) ?? .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    static func image(text: String, tone: MenuBarTone, accessibilityLabel: String) -> NSImage {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let size = NSSize(width: tileSize + gap + ceil(textSize.width), height: tileSize)
        // Drawn on demand, so it stays sharp at the display's scale and the plain number follows the menu bar's appearance.
        let image = NSImage(size: size, flipped: false) { _ in
            drawMark()
            let origin = NSPoint(x: tileSize + gap, y: ((tileSize - textSize.height) / 2).rounded())
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: color(for: tone)])
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    /// A placeholder until the icon lands: an amber, partly filled bar on the dark tile.
    private static func drawMark() {
        let tile = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: tileSize - 1, height: tileSize - 1), xRadius: 4, yRadius: 4)
        NSColor(srgbRed: 0x22 / 255, green: 0x1E / 255, blue: 0x1B / 255, alpha: 1).setFill()
        tile.fill()
        let track = NSRect(x: 4, y: 7, width: 10, height: 4)
        NSColor(srgbRed: 0x4A / 255, green: 0x3F / 255, blue: 0x35 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        NSColor(srgbRed: 0xF4 / 255, green: 0x8E / 255, blue: 0x48 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: 6.5, height: track.height), xRadius: 2, yRadius: 2).fill()
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
