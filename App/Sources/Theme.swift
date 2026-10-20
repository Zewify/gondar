import SwiftUI

/// The dark palette and type, shared by every view: the PortGlimpse tokens this app uses, and no others.
enum Theme {
    static let panel = Color(hex: 0x201B17)
    static let footer = Color(hex: 0x1B1714)
    static let text = Color(hex: 0xF6EDE3)
    static let softText = Color(hex: 0xD8CBBD)
    static let muted = Color(hex: 0xA8998A)
    static let line = Color(hex: 0x342C25)
    static let amber = Color(hex: 0xF48E48)

    static func title(_ size: CGFloat) -> Font { .custom("Bricolage Grotesque", size: size).weight(.heavy) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Figtree", size: size).weight(weight) }
    static func mono(_ size: CGFloat) -> Font { .custom("IBM Plex Mono", size: size).weight(.semibold) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
