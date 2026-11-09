import AppKit
import SwiftUI

/// Headless renders for design review and for building the app icon.
@MainActor
enum Snapshot {
    static func renderStates(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let americano = Drink.menu[2]
        let duration = americano.duration ?? 0
        let now = Date()

        let states: [(String, (Brewer) -> Void)] = [
            ("1-idle", { _ in }),
            ("2-pouring-early", { $0.pour(americano, at: now.addingTimeInterval(-0.35)) }),
            ("3-pouring-mid", { $0.pour(americano, at: now.addingTimeInterval(-1.0)) }),
            ("4-brewing-full", { $0.pour(americano, at: now.addingTimeInterval(-8)) }),
            ("5-brewing-62", { $0.pour(americano, at: now.addingTimeInterval(-0.38 * duration)) }),
            ("6-brewing-12", { $0.pour(americano, at: now.addingTimeInterval(-0.88 * duration)) }),
            ("7-draining", { brewer in
                brewer.pour(americano, at: now.addingTimeInterval(-0.3 * duration))
                brewer.finish(at: now.addingTimeInterval(-0.8))
            }),
            ("8-finished", { brewer in
                brewer.pour(americano, at: now.addingTimeInterval(-duration - 5))
                brewer.tick(now)
            }),
            ("9-bottomless", { $0.pour(Drink.menu[4], at: now.addingTimeInterval(-30)) }),
        ]

        for (name, setup) in states {
            let brewer = Brewer(keepsAwake: false)
            setup(brewer)
            let view = PourPanel(brewer: brewer)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            try write(view, scale: 2, to: directory.appendingPathComponent("\(name).png"))
        }

        let glyphs = HStack(spacing: 24) {
            ForEach([0.0, 0.35, 0.7, 1.0], id: \.self) { level in
                Image(nsImage: MenuBarGlyph.image(level: level, steam: level > 0 ? 1 : 0, time: 1.2))
                    .renderingMode(.template)
                    .foregroundStyle(.black)
            }
        }
        .padding(12)
        .background(Color(white: 0.93))
        try write(glyphs, scale: 6, to: directory.appendingPathComponent("glyphs.png"))
    }

    static func renderIconSet(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                try write(AppIcon().frame(width: 1024, height: 1024), scale: CGFloat(points * scale) / 1024, to: url)
            }
        }
    }

    private static func write(_ view: some View, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}

/// `Pour --selftest`: checks quiet scheduling and the real caffeinate lifecycle.
@MainActor
enum SelfTest {
    static func run() async -> Bool {
        let brewer = Brewer()
        let lastDrink = UserDefaults.standard.object(forKey: "lastDrink")
        defer {
            brewer.shutdown()
            if let lastDrink {
                UserDefaults.standard.set(lastDrink, forKey: "lastDrink")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastDrink")
            }
        }
        var passed = true
        func check(_ name: String, _ ok: Bool) {
            print("\(ok ? "PASS" : "FAIL")  \(name)")
            passed = passed && ok
        }

        let schedule = Brewer(keepsAwake: false)
        let now = Date()
        check("idle needs no background updates", schedule.statusUpdateInterval(at: now) == nil)
        schedule.pour(Drink(id: "schedule", name: "Schedule", duration: 180), at: now)
        check("pouring retains smooth short-lived updates", schedule.statusUpdateInterval(at: now).map { $0 > 0 && $0 < 0.1 } == true)
        check("settled timed cups update at most once a minute", schedule.statusUpdateInterval(at: now.addingTimeInterval(5)).map { $0 >= 60 } == true)
        check("the next update never skips the expiry deadline", schedule.statusUpdateInterval(at: now.addingTimeInterval(179.75)).map { $0 > 0 && $0 <= 0.25 } == true)
        schedule.tick(now.addingTimeInterval(180))
        check("expired cups stop background updates", !schedule.isAwake && schedule.statusUpdateInterval(at: now.addingTimeInterval(180)) == nil)

        let short = Drink(id: "short", name: "Short", duration: 10)
        schedule.pour(short, at: now)
        schedule.topUp(at: now.addingTimeInterval(8))
        schedule.tick(now.addingTimeInterval(11))
        check("top up survives the original deadline", schedule.isAwake && schedule.remaining(at: now.addingTimeInterval(11)) == 7)
        schedule.tick(now.addingTimeInterval(18))
        check("top up ends at the new deadline", !schedule.isAwake)

        schedule.pour(short, at: now)
        schedule.pour(Drink.menu[4], at: now.addingTimeInterval(5))
        schedule.tick(now.addingTimeInterval(11))
        check("switching to bottomless cancels timed updates", schedule.isAwake && schedule.statusUpdateInterval(at: now.addingTimeInterval(11)) == nil)
        schedule.pour(short, at: now.addingTimeInterval(12))
        schedule.tick(now.addingTimeInterval(22))
        check("switching from bottomless restores expiry", !schedule.isAwake)

        schedule.pour(Drink.menu[4], at: now)
        schedule.finish(at: now.addingTimeInterval(5))
        check("Finish retains its brief drain animation", schedule.statusUpdateInterval(at: now.addingTimeInterval(5.2)) != nil)
        let drainedAt = now.addingTimeInterval(5 + Brewer.drainDuration + 0.3)
        check("a drained cup stops both animation and background updates", !schedule.isAnimating(at: drainedAt) && schedule.statusUpdateInterval(at: drainedAt) == nil)

        brewer.pour(Drink(id: "test", name: "Test", duration: 3))
        let pid = brewer.caffeinatePID
        check("caffeinate starts on pour", pid != nil)
        if let pid {
            let args = shell("/bin/ps", "-o", "args=", "-p", String(pid))
            check("runs with -d -i -m -s -w <pour pid>", args.contains("caffeinate -d -i -m -s -w \(ProcessInfo.processInfo.processIdentifier)"))
            check("power assertion is held", shell("/usr/bin/pmset", "-g", "assertions").contains("pid \(pid)(caffeinate)"))
        }

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let pid { check("caffeinate expires without app polling", kill(pid, 0) != 0) }
        brewer.tick(.now)
        check("session ends when the cup is empty", !brewer.isAwake && brewer.finishedAt != nil)
        if let pid { check("caffeinate is gone after the cup empties", kill(pid, 0) != 0) }

        brewer.pour(Drink.menu[0])
        let second = brewer.caffeinatePID
        brewer.finish()
        try? await Task.sleep(for: .milliseconds(300))
        if let second { check("Finish stops caffeinate immediately", kill(second, 0) != 0) }
        check("Finish drains to empty", brewer.frame(at: .now.addingTimeInterval(Brewer.drainDuration)).level == 0)

        brewer.pour(Drink(id: "top-up", name: "Top up", duration: 2))
        let original = brewer.caffeinatePID
        try? await Task.sleep(for: .milliseconds(1200))
        brewer.topUp()
        let toppedUp = brewer.caffeinatePID
        check("top up replaces the caffeinate timeout", toppedUp != nil && toppedUp != original)
        try? await Task.sleep(for: .milliseconds(1100))
        check("the new assertion survives the old timeout", brewer.caffeinatePID == toppedUp && toppedUp != nil)
        brewer.finish()
        try? await Task.sleep(for: .milliseconds(300))
        if let toppedUp { check("Finish releases a topped-up assertion", kill(toppedUp, 0) != 0) }

        brewer.pour(Drink.menu[4])
        let interrupted = brewer.caffeinatePID
        check("bottomless starts its assertion", interrupted != nil)
        if let interrupted {
            check("the test can interrupt its own caffeinate", kill(interrupted, SIGTERM) == 0)
            let recoveryDeadline = Date().addingTimeInterval(2.5)
            while Date() < recoveryDeadline, brewer.caffeinatePID == nil || brewer.caffeinatePID == interrupted {
                try? await Task.sleep(for: .milliseconds(100))
            }
            check("bottomless recovers without background polling", brewer.caffeinatePID.map { $0 != interrupted } == true)
        }
        let finalPID = brewer.caffeinatePID
        brewer.shutdown()
        try? await Task.sleep(for: .milliseconds(300))
        check("shutdown releases the current assertion", brewer.caffeinatePID == nil)
        if let finalPID { check("shutdown leaves no caffeinate child", kill(finalPID, 0) != 0) }
        return passed
    }

    private static func shell(_ path: String, _ arguments: String...) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

/// The Finder icon: the same glass on a dark squircle, frozen mid-steam.
struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.13, green: 0.10, blue: 0.08), Color(red: 0.035, green: 0.03, blue: 0.026)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(RadialGradient(colors: [Color(red: 0.95, green: 0.6, blue: 0.28).opacity(0.28), .clear], center: UnitPoint(x: 0.45, y: 0.05), startRadius: 0, endRadius: 620))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)

            CupCanvas(frame: CupFrame(level: 0.74, steam: 1, residue: 0, time: 2.4))
                .frame(width: 800, height: 800)
                .offset(x: 14, y: -6)
        }
        .frame(width: 1024, height: 1024)
    }
}
