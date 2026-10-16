// Launches an app executable and prints "<pid> <milliseconds>" once the notch window is on screen.
// The app keeps running; the caller measures it further and stops it. Used by scripts/benchmark.sh.
// Usage: launch-probe <executable> [window-layer] [timeout-seconds]
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: launch-probe <executable> [window-layer] [timeout-seconds]\n".utf8))
    exit(2)
}
// The notch panel sits at the main menu level + 3 (NotchPanel.swift); the menu bar icon is lower.
let layer = arguments.count > 2 ? Int(arguments[2]) ?? 27 : 27
let timeout = arguments.count > 3 ? Double(arguments[3]) ?? 20 : 20

let process = Process()
process.executableURL = URL(fileURLWithPath: arguments[1])
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice

let start = DispatchTime.now().uptimeNanoseconds
try process.run()
let pid = process.processIdentifier

while true {
    let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    if milliseconds > timeout * 1000 {
        print("\(pid) timeout")
        exit(1)
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let shown = windows.contains {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == layer
    }
    if shown {
        print("\(pid) \(Int(milliseconds.rounded()))")
        exit(0)
    }
    usleep(2_000)
}
