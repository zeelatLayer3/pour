import Foundation
import Observation

struct Drink: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let duration: TimeInterval?

    var label: String {
        guard let duration else { return "∞" }
        let minutes = Int(duration / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    static let menu: [Drink] = [
        Drink(id: "espresso", name: "Espresso", duration: 30 * 60),
        Drink(id: "cortado", name: "Cortado", duration: 60 * 60),
        Drink(id: "americano", name: "Americano", duration: 2 * 60 * 60),
        Drink(id: "carafe", name: "Carafe", duration: 4 * 60 * 60),
        Drink(id: "bottomless", name: "Bottomless", duration: nil),
    ]
}

/// Everything the glass needs to draw one frame.
struct CupFrame: Sendable {
    struct Stream: Sendable {
        /// 0 is the top of the canvas, 1 is the liquid surface.
        var top: Double
        var bottom: Double
        var thickness: Double
    }

    var level: Double = 0
    var steam: Double = 0
    var residue: Double = 0
    var stream: Stream?
    var ripple: Double?
    var wobble: Double = 0
    var time: Double = 0
}

@MainActor
@Observable
final class Brewer {
    struct Session {
        let drink: Drink
        var endDate: Date?
        var pourStart: Date
        var pourFrom: Double
        var washesResidue: Bool
    }

    static let pourDuration: TimeInterval = 2.1
    static let drainDuration: TimeInterval = 1.6

    private(set) var session: Session?
    private(set) var drainStart: Date?
    private(set) var drainFrom: Double = 0
    private(set) var finishedAt: Date?

    private let caffeinator: Caffeinator

    init(keepsAwake: Bool = true) {
        caffeinator = Caffeinator(enabled: keepsAwake)
    }

    var isAwake: Bool { session != nil }
    var caffeinatePID: Int32? { caffeinator.pid }

    func pour(_ drink: Drink, at now: Date = .now) {
        let from = session.map { level(of: $0, at: now) } ?? 0
        session = Session(
            drink: drink,
            endDate: drink.duration.map { now.addingTimeInterval($0) },
            pourStart: now,
            pourFrom: from,
            washesResidue: session == nil && finishedAt != nil
        )
        drainStart = nil
        finishedAt = nil
        caffeinator.start(until: session?.endDate)
        UserDefaults.standard.set(drink.id, forKey: "lastDrink")
    }

    func topUp(at now: Date = .now) {
        guard let drink = session?.drink else { return }
        pour(drink, at: now)
    }

    func finish(at now: Date = .now) {
        guard let session else { return }
        drainFrom = level(of: session, at: now)
        drainStart = now
        end(at: now)
    }

    /// Called on every tick. Ends the session the moment the cup runs dry and keeps caffeinate alive until then.
    func tick(_ now: Date) {
        if let drainStart, now.timeIntervalSince(drainStart) >= Self.drainDuration + 0.2 {
            self.drainStart = nil
        }
        guard let session else { return }
        if let end = session.endDate, now >= end {
            drainFrom = 0
            drainStart = nil
            self.end(at: now)
        } else {
            caffeinator.start(until: session.endDate)
        }
    }

    /// Only short transitions need animation ticks. Timed cups update once a minute or at expiry.
    func statusUpdateInterval(at now: Date) -> TimeInterval? {
        let remaining = remaining(at: now)
        if let remaining, remaining <= 0 { return nil }
        if isInMotion(at: now) { return min(1.0 / 30, remaining ?? .infinity) }
        return remaining.map { min(60, $0) }
    }

    /// True while liquid is visibly moving: a pour, a top up, or a drain.
    func isInMotion(at now: Date) -> Bool {
        if let session { return now.timeIntervalSince(session.pourStart) < Self.pourDuration + 1.5 }
        guard let drainStart else { return false }
        return now.timeIntervalSince(drainStart) < Self.drainDuration + 0.2
    }

    func isAnimating(at now: Date) -> Bool {
        if session != nil { return true }
        guard let drainStart else { return false }
        return now.timeIntervalSince(drainStart) < Self.drainDuration + 0.2
    }

    func remaining(at now: Date) -> TimeInterval? {
        guard let end = session?.endDate else { return nil }
        return max(0, end.timeIntervalSince(now))
    }

    func frame(at now: Date) -> CupFrame {
        var frame = CupFrame(time: now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))

        if let session {
            let p = clamp(now.timeIntervalSince(session.pourStart) / Self.pourDuration)
            let rise = easeOutCubic(clamp((p - 0.08) / 0.84))
            frame.level = lerp(session.pourFrom, level(of: session, at: now), rise)

            let head = clamp(p / 0.09)
            let tail = clamp((p - 0.78) / 0.13)
            if tail < 1 {
                frame.stream = .init(
                    top: tail * tail,
                    bottom: head * head,
                    thickness: 1 - 0.45 * clamp((p - 0.62) / 0.2)
                )
                if head >= 1 { frame.ripple = (now.timeIntervalSince(session.pourStart) * 1.4).truncatingRemainder(dividingBy: 1) }
            }

            let settle = max(0, now.timeIntervalSince(session.pourStart) - Self.pourDuration * 0.6)
            frame.wobble = 2.2 * exp(-settle * 1.7) * (head >= 1 ? 1 : 0)
            let warmUp = session.pourFrom > 0.05 ? 1 : smoothstep(0.25, 1, p)
            frame.steam = steam(for: frame.level) * warmUp
            frame.residue = session.washesResidue ? 1 - smoothstep(0, 0.7, p) : 0
        } else if let drainStart {
            let p = clamp(now.timeIntervalSince(drainStart) / Self.drainDuration)
            frame.level = drainFrom * (1 - easeInOutCubic(p))
            frame.steam = steam(for: frame.level)
            frame.residue = smoothstep(0, 1, p)
        } else if finishedAt != nil {
            frame.residue = 1
        }
        return frame
    }

    private func level(of session: Session, at now: Date) -> Double {
        guard let end = session.endDate, let duration = session.drink.duration else { return 1 }
        return clamp(end.timeIntervalSince(now) / duration)
    }

    private func steam(for level: Double) -> Double {
        smoothstep(0, 0.18, level)
    }

    private func end(at now: Date) {
        session = nil
        finishedAt = now
        caffeinator.stop()
    }

    func shutdown() {
        caffeinator.stop()
    }
}

/// Owns one `caffeinate` child process. `-w` ties it to this app, so it can never outlive Pour.
@MainActor
final class Caffeinator {
    private let enabled: Bool
    private var process: Process?
    private var endDate: Date?

    init(enabled: Bool) { self.enabled = enabled }

    var pid: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    func start(until endDate: Date? = nil) {
        guard enabled else { return }
        guard process?.isRunning != true || self.endDate != endDate else { return }
        stop()
        guard endDate.map({ $0 > .now }) ?? true else { return }
        self.endDate = endDate
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d", "-i", "-m", "-s", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        if let endDate {
            // The child releases its assertions on time even if macOS defers this app's timers.
            process.arguments?.append(contentsOf: ["-t", String(max(1, Int(ceil(endDate.timeIntervalSinceNow))))])
        }
        process.terminationHandler = { [weak self] terminated in
            Task { @MainActor in
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.process === terminated else { return }
                self.process = nil
                self.start(until: self.endDate)
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("Pour: could not start caffeinate: \(error.localizedDescription)")
        }
    }

    func stop() {
        let previous = process
        process = nil
        previous?.terminate()
    }
}

func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(max(x, lo), hi) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
func easeInOutCubic(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}
