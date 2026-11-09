import ServiceManagement
import SwiftUI

enum Ink {
    static let crema = Color(red: 0.86, green: 0.66, blue: 0.44)
    static let ground = Color(red: 0.047, green: 0.038, blue: 0.033)
    static let tile = Color.white.opacity(0.035)
    static let hairline = Color.white.opacity(0.07)
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.48)
    static let tertiary = Color.white.opacity(0.28)
}

/// The panel is a small bento: the cup and its status side by side, the drinks below.
struct PourPanel: View {
    let brewer: Brewer
    var otherCaffeinates: Int = 0
    var onQuit: () -> Void = {}

    @AppStorage("showTimeInMenuBar") private var showTime = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    static let width: CGFloat = 376
    private let cupSide: CGFloat = 200
    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !brewer.isAnimating(at: .now))) { timeline in
                    let now = timeline.date
                    HStack(spacing: 8) {
                        CupCanvas(frame: brewer.frame(at: now))
                            .frame(width: cupSide, height: cupSide)
                            .background(cupLight)
                            .tile()
                        status(at: now)
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Ink.tile)
                            .tile()
                    }
                    .frame(height: cupSide)
                }

                drinks

                if otherCaffeinates > 0 {
                    notice("Another caffeinate is running, so this Mac stays awake after your cup is empty.")
                }
                if let loginError {
                    notice(loginError)
                }
            }
            .padding(12)

            footer
        }
        .frame(width: Self.width)
        .background(Ink.ground)
        .animation(spring, value: brewer.session?.drink)
        .preferredColorScheme(.dark)
    }

    private var cupLight: some View {
        ZStack {
            Ink.tile
            RadialGradient(
                colors: [Color(red: 0.95, green: 0.62, blue: 0.30).opacity(0.2), .clear],
                center: UnitPoint(x: 0.38, y: 0),
                startRadius: 0,
                endRadius: 200
            )
        }
    }

    // MARK: Status

    @ViewBuilder
    private func status(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session = brewer.session {
                eyebrow(session.drink.name, color: Ink.crema)
                Text(brewer.remaining(at: now).map(Clock.long) ?? "∞")
                    .font(.system(size: session.endDate == nil ? 38 : 30, weight: .ultraLight))
                    .monospacedDigit()
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 40, alignment: .leading)
                    .padding(.top, 10)
                Text(session.endDate.map { "until \($0.formatted(date: .omitted, time: .shortened))" } ?? "until you finish")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.secondary)
                Spacer(minLength: 8)
                VStack(spacing: 6) {
                    Button("Finish") { withAnimation(spring) { brewer.finish() } }
                        .buttonStyle(ActionStyle(prominent: true))
                        .keyboardShortcut(.return, modifiers: [])
                        .help("Drain the cup and let your Mac sleep")
                    if session.drink.duration != nil {
                        Button("Top up") { withAnimation(spring) { brewer.topUp() } }
                            .buttonStyle(ActionStyle(prominent: false))
                            .help("Refill to a full \(session.drink.name.lowercased())")
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                let finished = brewer.finishedAt != nil
                eyebrow(finished ? "Empty" : "Ready", color: Ink.tertiary)
                Text(finished ? "Last drop" : "Pick a cup")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Ink.primary)
                    .frame(height: 40, alignment: .leading)
                    .padding(.top, 10)
                Text(finished ? "Caffeinate is off. Your Mac can rest." : "Your screen stays on until it's empty.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick pour")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ink.tertiary)
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { key in
                            Text("\(key)")
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Ink.secondary)
                                .frame(width: 18, height: 18)
                                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 0.5))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(color)
    }

    // MARK: Drinks

    private var drinks: some View {
        HStack(spacing: 6) {
            ForEach(Array(Drink.menu.enumerated()), id: \.element.id) { index, drink in
                Button {
                    withAnimation(spring) { brewer.pour(drink) }
                } label: {
                    VStack(spacing: 3) {
                        Text(drink.label)
                            .font(.system(size: 15, weight: .regular))
                            .monospacedDigit()
                            .foregroundStyle(Ink.primary)
                        Text(drink.name)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(ChipStyle(isSelected: brewer.session?.drink == drink))
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                .help(drink.duration == nil ? "Keep the screen on until you finish" : "Keep the screen on for \(drink.label)")
            }
        }
    }

    private func notice(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Ink.crema).frame(width: 5, height: 5).offset(y: -1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ink.crema.opacity(0.06))
        .tile(stroke: Ink.crema.opacity(0.16))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            FooterToggle(title: "Open at login", isOn: opensAtLogin) { setOpensAtLogin(!opensAtLogin) }
            FooterToggle(title: "Menu bar timer", isOn: showTime) { showTime.toggle() }
            Spacer()
            Button("Quit", action: onQuit)
                .buttonStyle(FooterButtonStyle())
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 0.5) }
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change Open at login. Move Pour to Applications and try again."
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private extension View {
    func tile(stroke: Color = Ink.hairline) -> some View {
        clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(stroke, lineWidth: 0.5))
    }
}

enum Clock {
    static func long(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes >= 60 { return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" }
        return "\(minutes)m"
    }
}

// MARK: Styles

private struct ChipStyle: ButtonStyle {
    let isSelected: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Ink.crema.opacity(0.14) : Color.white.opacity(hovering ? 0.085 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Ink.crema.opacity(0.55) : Color.white.opacity(hovering ? 0.12 : 0.07), lineWidth: 0.75)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

private struct ActionStyle: ButtonStyle {
    let prominent: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(prominent ? Ink.ground : Ink.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? Ink.crema.opacity(hovering ? 1 : 0.9) : Color.white.opacity(hovering ? 0.1 : 0.06))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

private struct FooterButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(hovering ? Ink.primary : Ink.secondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

private struct FooterToggle: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(isOn ? Ink.crema : Color.white.opacity(0.14))
                    .frame(width: 18, height: 10)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(isOn ? Ink.ground : Color.white.opacity(0.7)).frame(width: 7, height: 7).padding(1.5)
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
                Text(title)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(FooterButtonStyle())
    }
}
