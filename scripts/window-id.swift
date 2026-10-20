// Prints "<CGWindowID> <layer> <width>x<height>" for every on-screen window of one process, for `screencapture -l`.
// Usage: swift scripts/window-id.swift <pid>. By process ID, because the demo runs beside an installed Gondar with the same name.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: window-id.swift <pid>\n".data(using: .utf8)!)
    exit(2)
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerPID as String] as? Int) == pid {
    guard let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Double],
          let layer = window[kCGWindowLayer as String] as? Int, layer != 25 else { continue } // 25 = the status item
    print("\(id) \(layer) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))")
}
