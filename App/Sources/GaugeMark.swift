import CoreGraphics

/// Gondar's mark: an amber gauge on TickThock's dark tile, PortGlimpse's colourway.
/// The one source of its geometry, shared by the menu bar icon and `scripts/make-icon.swift`,
/// which compiles this file beside it, so the two cannot drift apart.
/// Everything is in points on the 18-point menu bar tile, y up; the app icon scales it by 824 / 18 about the centre.
enum GaugeMark {
    /// Menu bar icons are 18 points tall; the tile is inset half a point with a 4-point corner, as PortGlimpse's.
    static let tileSize: CGFloat = 18
    static let tileInset: CGFloat = 0.5
    static let tileCornerRadius: CGFloat = 4

    /// A 240° arc open at the bottom, its stroke centred on this radius.
    static let radius: CGFloat = 4.8
    /// 2.4 points: more than two device pixels even at 1x, so it survives antialiasing, and thin enough to leave
    /// the gauge an open centre rather than a horseshoe. Radius plus half the stroke is a whole 6 points, so the
    /// arc's outer left, right and top edges fall on pixel boundaries at 1x and 2x and stay crisp.
    static let lineWidth: CGFloat = 2.4
    static let sweep: CGFloat = 240
    /// How much of the track the amber arc fills, from the left end over the top.
    static let fillFraction: CGFloat = 0.6
    /// The arc's ink spans 1.5 radii plus a stroke vertically (4.4 to 14 points), its middle a quarter radius above
    /// the arc's centre; one point below the tile's centre puts the ink within 0.2 points of centred with its top edge on a whole point.
    static let centre = CGPoint(x: 9, y: 8)

    static let tileColor: UInt32 = 0x221E1B
    static let trackColor: UInt32 = 0x4A3F35
    static let amber: UInt32 = 0xF48E48

    static func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// The menu bar tile, its rounded square and the gauge, in an 18-point square at the origin.
    static func drawMenuBarIcon(in ctx: CGContext) {
        let tile = CGRect(x: 0, y: 0, width: tileSize, height: tileSize).insetBy(dx: tileInset, dy: tileInset)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: tileCornerRadius, cornerHeight: tileCornerRadius, transform: nil))
        ctx.setFillColor(color(tileColor))
        ctx.fillPath()
        drawGauge(in: ctx)
    }

    /// The track, then the amber fill over it, both with round ends.
    static func drawGauge(in ctx: CGContext) {
        let start = degrees(90 + sweep / 2)
        ctx.saveGState()
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: centre, radius: radius, startAngle: start, endAngle: degrees(90 - sweep / 2), clockwise: true)
        ctx.setStrokeColor(color(trackColor))
        ctx.strokePath()
        ctx.addArc(center: centre, radius: radius, startAngle: start, endAngle: start - degrees(sweep * fillFraction), clockwise: true)
        ctx.setStrokeColor(color(amber))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func degrees(_ value: CGFloat) -> CGFloat { value * .pi / 180 }
}
