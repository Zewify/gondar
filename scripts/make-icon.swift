// Renders AppIcon.appiconset: the menu bar's gauge mark at app icon size, from the shared geometry in
// App/Sources/GaugeMark.swift, which is why this is compiled with it rather than run as a script.
// Usage: ./scripts/make-icon.sh (it builds this with that file and writes App/Resources/Assets.xcassets/AppIcon.appiconset).
import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
        var images: [[String: String]] = []
        for (points, scale) in sizes {
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
            images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
        }
        let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Contents.json"))
        print("Wrote \(sizes.count) icons to \(output.path)")
    }

    static func render(pixels: Int) -> Data {
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        // macOS icon grid: an 824-point tile inset 100 points in the 1024 canvas.
        ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.setFillColor(GaugeMark.color(GaugeMark.tileColor))
        ctx.fillPath()
        // The menu bar icon's proportions, as PortGlimpse's: its 18-point square scaled to the 824-point tile about the centre,
        // so the gauge's radius is 4.8 × 824 / 18 ≈ 220 and its stroke 2.4 × 824 / 18 ≈ 110.
        ctx.translateBy(x: 512, y: 512)
        ctx.scaleBy(x: 824 / GaugeMark.tileSize, y: 824 / GaugeMark.tileSize)
        ctx.translateBy(x: -GaugeMark.tileSize / 2, y: -GaugeMark.tileSize / 2)
        GaugeMark.drawGauge(in: ctx)
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }
}
