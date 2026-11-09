import AppKit

let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
    try Snapshot.renderStates(to: URL(fileURLWithPath: arguments[index + 1]))
    exit(0)
}

if let index = arguments.firstIndex(of: "--iconset"), arguments.indices.contains(index + 1) {
    try Snapshot.renderIconSet(to: URL(fileURLWithPath: arguments[index + 1]))
    exit(0)
}

if arguments.contains("--selftest") {
    exit(await SelfTest.run() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
