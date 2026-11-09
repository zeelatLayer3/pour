import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let brewer = Brewer()
    private var statusItem: NSStatusItem!
    private var panel: PourWindow?
    private var ticker: Task<Void, Never>?
    private var lastClose = Date.distantPast
    private var otherCaffeinates = 0
    private var panelPresentation = 0

    private static let itemName = "Pour"

    func applicationDidFinishLaunching(_ notification: Notification) {
        placeStatusItemClearOfNotch()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.itemName
        statusItem.isVisible = true
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.imagePosition = .imageLeading
        refreshStatusItem(at: .now)

        withObservationTracking { _ = brewer.session; _ = brewer.drainStart } onChange: { [weak self] in
            Task { @MainActor in self?.brewerChanged() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatusItem(at: .now) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startTicking() }
        }
        registerLoginItemOnFirstLaunch()
    }

    /// New items join the left end of the menu bar, the first place a notched MacBook hides them.
    /// Until the cup is Command-dragged somewhere else, start it beside the system items on the right.
    private func placeStatusItemClearOfNotch() {
        let key = "NSStatusItem Preferred Position \(Self.itemName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(Self.preferredPosition, forKey: key)
    }

    private static let preferredPosition: Double = 180

    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            NSLog("Pour: could not register as a login item: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ticker?.cancel()
        brewer.shutdown()
    }

    private func brewerChanged() {
        withObservationTracking { _ = brewer.session; _ = brewer.drainStart } onChange: { [weak self] in
            Task { @MainActor in self?.brewerChanged() }
        }
        startTicking()
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                let now = Date()
                self.brewer.tick(now)
                self.refreshStatusItem(at: now)
                guard let interval = self.brewer.statusUpdateInterval(at: now) else {
                    self.ticker = nil
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    private func refreshStatusItem(at now: Date) {
        guard let button = statusItem?.button else { return }
        let frame = brewer.frame(at: now)
        // A settled cup is static; steam should not keep the menu bar redrawing all day.
        let time = brewer.isInMotion(at: now) ? frame.time : 0
        button.image = MenuBarGlyph.image(level: frame.level, steam: frame.steam, time: time)
        let showTime = UserDefaults.standard.bool(forKey: "showTimeInMenuBar")
        if showTime, let remaining = brewer.remaining(at: now) {
            button.title = Clock.short(remaining)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            button.title = ""
        }
        button.toolTip = brewer.remaining(at: now).map { "Pour: \(Clock.long($0)) left" } ?? (brewer.isAwake ? "Pour: bottomless" : "Pour")
    }

    // MARK: Panel

    @objc private func toggle() {
        if let panel, panel.isVisible {
            close()
        } else if Date().timeIntervalSince(lastClose) > 0.25 {
            open()
        }
    }

    private func open() {
        panelPresentation += 1
        brewer.tick(.now)
        let host = PourHostingView(rootView: makePanel())
        host.onResize = { [weak self] in self?.resizePanel() }
        let size = host.fittingSize

        let panel = self.panel ?? PourWindow()
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }
        panel.contentView = host
        host.wantsLayer = true
        host.layer?.cornerRadius = 20
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        host.layer?.borderWidth = 0.5
        host.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        self.panel = panel

        let target = panelFrame(for: size)
        panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        statusItem.button?.highlight(true)
        checkOtherCaffeinates()
    }

    private func close() {
        guard let panel, panel.isVisible else { return }
        panelPresentation += 1
        let presentation = panelPresentation
        lastClose = Date()
        statusItem.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard self?.panelPresentation == presentation, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
                // Hidden hosting views retain their timelines. Remove the view to stop rendering.
                panel.contentView = nil
            }
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func makePanel() -> PourPanel {
        PourPanel(brewer: brewer, otherCaffeinates: otherCaffeinates) { NSApp.terminate(nil) }
    }

    private func panelFrame(for size: NSSize) -> NSRect {
        guard let buttonWindow = statusItem.button?.window else { return NSRect(origin: .zero, size: size) }
        let anchor = buttonWindow.frame
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let y = anchor.minY - size.height - 6
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func checkOtherCaffeinates() {
        let own = brewer.caffeinatePID
        Task { @MainActor in
            let pids = await Self.caffeinatePIDs()
            let others = pids.filter { $0 != own }.count
            guard others != otherCaffeinates else { return }
            otherCaffeinates = others
            guard panel?.isVisible == true, panel?.alphaValue != 0 else { return }
            (panel?.contentView as? PourHostingView)?.rootView = makePanel()
        }
    }

    private func resizePanel() {
        guard let panel, panel.isVisible, let host = panel.contentView else { return }
        let target = panelFrame(for: host.fittingSize)
        guard abs(target.height - panel.frame.height) > 0.5 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().setFrame(target, display: true)
        }
    }

    nonisolated private static func caffeinatePIDs() async -> [Int32] {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-x", "caffeinate"]
            process.standardOutput = pipe
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return []
            }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        }.value
    }
}

/// Reports SwiftUI size changes so the panel can grow downward from the menu bar.
final class PourHostingView: NSHostingView<PourPanel> {
    var onResize: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}

/// A borderless panel that floats under the menu bar like a system extra.
final class PourWindow: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
