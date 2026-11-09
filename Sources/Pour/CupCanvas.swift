import SwiftUI

private struct RGB {
    let r: Double, g: Double, b: Double
    func color(_ opacity: Double = 1) -> Color { Color(red: r, green: g, blue: b).opacity(opacity) }
}

private enum Palette {
    static let coffeeDeep = RGB(r: 0.11, g: 0.055, b: 0.03)
    static let coffee = RGB(r: 0.19, g: 0.095, b: 0.05)
    static let coffeeEdge = RGB(r: 0.42, g: 0.22, b: 0.10)
    static let amber = RGB(r: 0.86, g: 0.52, b: 0.22)
    static let crema = RGB(r: 0.80, g: 0.58, b: 0.36)
    static let cremaDeep = RGB(r: 0.52, g: 0.31, b: 0.15)
    static let steam = RGB(r: 1.0, g: 0.96, b: 0.90)
}

/// A clear glass cup on a glass saucer, seen from slightly above. Designed on a 208pt square and scaled.
struct CupCanvas: View {
    var frame: CupFrame

    var body: some View {
        Canvas { context, size in
            CupPainter(frame: frame, size: size).paint(in: &context)
        }
    }
}

private struct CupPainter {
    let frame: CupFrame
    let size: CGSize

    var u: CGFloat { min(size.width, size.height) / 208 }
    var cx: CGFloat { size.width / 2 - 4 * u }
    var yb: CGFloat { size.height / 2 + 49 * u }
    var height: CGFloat { 72 * u }
    var rimR: CGFloat { 54 * u }
    var waistR: CGFloat { 49 * u }
    var corner: CGFloat { 18 * u }
    var wall: CGFloat { 2.4 * u }
    var base: CGFloat { 6 * u }
    let k: CGFloat = 0.28
    var fullH: CGFloat { height - 11 * u }
    var t: Double { frame.time }

    func outer(_ h: CGFloat) -> CGFloat { profile(h, height, rimR, waistR, corner) }
    func inner(_ h: CGFloat) -> CGFloat { profile(h - base, height - base, rimR - wall, waistR - wall, corner - wall) }
    func liquidHeight(_ level: Double) -> CGFloat { base + CGFloat(level) * (fullH - base) }

    func point(_ h: CGFloat, _ phi: Double, _ r: CGFloat) -> CGPoint {
        CGPoint(x: cx + r * CGFloat(cos(phi)), y: yb - h + r * k * CGFloat(sin(phi)))
    }

    // MARK: Paint

    func paint(in context: inout GraphicsContext) {
        paintSaucer(in: &context)
        paintCupBack(in: &context)
        if frame.residue > 0.001 { paintResidue(in: &context) }
        if frame.level > 0.002 { paintCoffee(in: &context) }
        paintBase(in: &context)
        paintHandle(in: &context)
        paintCupFront(in: &context)
        if let stream = frame.stream { paintStream(stream, in: &context) }
        if frame.steam > 0.01 { paintSteam(in: &context) }
    }

    private func paintSaucer(in context: inout GraphicsContext) {
        let center = CGPoint(x: cx, y: yb + 3 * u)
        let r = 80 * u
        let plate = ellipse(center, r)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10 * u))
            layer.fill(ellipse(CGPoint(x: center.x + 8 * u, y: center.y + 8 * u), r * 0.98), with: .color(.black.opacity(0.6)))
        }

        var underside = Path()
        append(arcPoints(center: CGPoint(x: center.x, y: center.y + 3.5 * u), r: r * 0.97, from: 0, to: .pi), to: &underside)
        append(arcPoints(center: center, r: r, from: .pi, to: 0), to: &underside)
        underside.closeSubpath()
        context.fill(underside, with: .color(.white.opacity(0.06)))

        context.fill(
            plate,
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.07), .white.opacity(0.02)]),
                center: CGPoint(x: center.x - r * 0.35, y: center.y - r * k * 0.5),
                startRadius: 0,
                endRadius: r * 1.1
            )
        )

        if frame.level > 0.01 {
            context.drawLayer { layer in
                layer.clip(to: plate)
                layer.addFilter(.blur(radius: 7 * u))
                layer.fill(
                    ellipse(CGPoint(x: cx + 24 * u, y: center.y + 7 * u), 34 * u, ratio: 0.32),
                    with: .color(Palette.amber.color(0.34 * frame.level))
                )
            }
        }

        context.stroke(ellipse(CGPoint(x: center.x, y: center.y - 0.6 * u), waistR * 1.22), with: .color(.white.opacity(0.07)), lineWidth: 0.8 * u)
        context.stroke(arc(center: center, r: r, from: .pi, to: 2 * .pi), with: .color(.white.opacity(0.22)), lineWidth: 0.8 * u)
        context.stroke(arc(center: center, r: r, from: 0, to: .pi), with: .color(.white.opacity(0.5)), lineWidth: 1 * u)
        context.stroke(arc(center: CGPoint(x: center.x, y: center.y + 3.5 * u), r: r * 0.97, from: 0.2, to: .pi - 0.2), with: .color(.white.opacity(0.16)), lineWidth: 0.8 * u)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 4 * u))
            layer.fill(ellipse(CGPoint(x: cx + 3 * u, y: yb + 1.5 * u), outer(0) * 1.1), with: .color(.black.opacity(0.5)))
        }
    }

    private func paintCupBack(in context: inout GraphicsContext) {
        context.fill(closed(outline(from: 0, to: height, radius: outer)), with: .color(.white.opacity(0.035)))
        context.stroke(arc(center: center(height), r: rimR, from: .pi, to: 2 * .pi), with: .color(.white.opacity(0.24)), lineWidth: 1 * u)
        context.stroke(arc(center: center(height), r: rimR - wall, from: .pi, to: 2 * .pi), with: .color(.white.opacity(0.1)), lineWidth: 0.7 * u)
        context.stroke(arc(center: center(base), r: inner(base), from: .pi, to: 2 * .pi), with: .color(.white.opacity(0.1)), lineWidth: 0.7 * u)
    }

    private func paintResidue(in context: inout GraphicsContext) {
        let o = frame.residue
        let low = liquidHeight(max(frame.level, 0))
        if fullH - low > 1 {
            let band = closed(outline(from: low, to: fullH, radius: inner))
            context.fill(
                band,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Palette.coffeeEdge.color(0.15 * o), location: 0),
                        .init(color: Palette.coffeeEdge.color(0.045 * o), location: 0.18),
                        .init(color: Palette.coffeeEdge.color(0.035 * o), location: 0.8),
                        .init(color: Palette.coffeeEdge.color(0.1 * o), location: 1),
                    ]),
                    startPoint: CGPoint(x: cx, y: yb - fullH - inner(fullH) * k),
                    endPoint: CGPoint(x: cx, y: yb - low + inner(low) * k)
                )
            )
            context.stroke(ellipse(center(fullH), inner(fullH)), with: .color(Palette.coffeeEdge.color(0.42 * o)), lineWidth: 0.9 * u)
        }
        if frame.level < 0.01 {
            let ring = ellipse(center(base + 0.6 * u), inner(base + 0.6 * u) * 0.96)
            context.fill(ring, with: .color(Palette.coffee.color(0.42 * o)))
            context.stroke(ring, with: .color(Palette.coffeeEdge.color(0.5 * o)), lineWidth: 1 * u)
        }
    }

    private func paintCoffee(in context: inout GraphicsContext) {
        let lh = liquidHeight(frame.level)
        let surfaceY = yb - lh
        let hL = inner(lh)
        let tilt = frame.wobble * u * sin(t * 8.5) + 0.3 * u * sin(t * 1.3)
        let floorY = yb - base

        func slosh(_ p: CGPoint) -> CGPoint {
            let weight = clamp(Double((floorY - p.y) / max(floorY - surfaceY, 1)))
            return CGPoint(x: p.x, y: p.y + tilt * (p.x - cx) / max(hL, 1) * CGFloat(weight))
        }

        let body = closed(outline(from: base, to: lh, radius: inner).map(slosh))
        context.fill(
            body,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Palette.coffeeEdge.color(), location: 0),
                    .init(color: Palette.coffee.color(), location: 0.16),
                    .init(color: Palette.coffeeDeep.color(), location: 0.6),
                    .init(color: Palette.coffee.color(), location: 0.9),
                    .init(color: Palette.coffeeEdge.color(0.9), location: 1),
                ]),
                startPoint: CGPoint(x: cx - hL, y: 0),
                endPoint: CGPoint(x: cx + hL, y: 0)
            )
        )

        context.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(
                body,
                with: .linearGradient(
                    Gradient(colors: [.clear, .black.opacity(0.38)]),
                    startPoint: CGPoint(x: cx, y: surfaceY),
                    endPoint: CGPoint(x: cx, y: floorY + inner(base) * k)
                )
            )
            layer.drawLayer { glow in
                glow.addFilter(.blur(radius: 4 * u))
                var edge = Path()
                append(stride(from: lh, through: base + corner * 0.4, by: -2 * u).map { point($0, .pi * 0.97, inner($0)) }, to: &edge)
                glow.stroke(edge, with: .color(Palette.amber.color(0.5)), lineWidth: 6 * u)
            }
        }

        let cremaDepth = min(5.5 * u, (lh - base) * 0.3)
        if cremaDepth > 0.4 {
            let lower = lh - cremaDepth
            var band = Path()
            append(surfacePoints(surfaceY, hL, tilt, from: 0, to: .pi), to: &band)
            append(surfacePoints(yb - lower, inner(lower), tilt, from: .pi, to: 0), to: &band)
            band.closeSubpath()
            context.fill(
                band,
                with: .linearGradient(
                    Gradient(colors: [Palette.crema.color(0.95), Palette.cremaDeep.color(0)]),
                    startPoint: CGPoint(x: cx, y: surfaceY + hL * k),
                    endPoint: CGPoint(x: cx, y: surfaceY + hL * k + cremaDepth)
                )
            )
        }

        let surface = closed(surfacePoints(surfaceY, hL, tilt, from: 0, to: 2 * .pi))
        context.fill(
            surface,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Palette.crema.color(), location: 0),
                    .init(color: Palette.crema.color(0.96), location: 0.55),
                    .init(color: Palette.cremaDeep.color(), location: 1),
                ]),
                center: CGPoint(x: cx - hL * 0.12, y: surfaceY - hL * k * 0.15),
                startRadius: 0,
                endRadius: hL * 1.02
            )
        )

        context.drawLayer { layer in
            layer.clip(to: surface)
            layer.addFilter(.blur(radius: 2.5 * u))
            let drift = CGFloat(0.05 * sin(t * 0.9))
            layer.fill(
                Path(ellipseIn: CGRect(x: cx - hL * (0.6 - drift), y: surfaceY - hL * k * 0.72, width: hL * 0.72, height: hL * k * 0.62)),
                with: .color(.white.opacity(0.24))
            )
        }

        paintBubbles(surfaceY: surfaceY, hL: hL, tilt: tilt, in: &context)

        if let ripple = frame.ripple, let stream = frame.stream, stream.bottom >= 1 {
            for offset in [0.0, 0.5] {
                let r = (ripple + offset).truncatingRemainder(dividingBy: 1)
                let rx = 3 * u + CGFloat(r) * hL * 0.8
                let impact = CGPoint(x: streamX, y: surfaceY + tilt * (streamX - cx) / max(hL, 1))
                context.stroke(
                    Path(ellipseIn: CGRect(x: impact.x - rx, y: impact.y - rx * k, width: rx * 2, height: rx * k * 2)),
                    with: .color(Palette.crema.color(0.5 * (1 - r) * stream.thickness)),
                    lineWidth: 0.8 * u
                )
            }
        }

        context.stroke(surface, with: .color(Palette.coffeeDeep.color(0.5)), lineWidth: 1 * u)
    }

    private func paintBubbles(surfaceY: CGFloat, hL: CGFloat, tilt: CGFloat, in context: inout GraphicsContext) {
        let bubbles: [(angle: Double, radius: CGFloat, size: CGFloat)] = [
            (0.3, 0.88, 1.2), (0.6, 0.9, 0.8), (1.25, 0.86, 1.0), (2.35, 0.86, 1.0), (2.75, 0.9, 1.5),
            (3.55, 0.82, 0.8), (4.1, 0.88, 1.1), (4.9, 0.8, 0.7), (5.3, 0.86, 0.9), (5.8, 0.8, 1.3),
        ]
        for bubble in bubbles {
            let a = bubble.angle + t * 0.03
            let x = cx + CGFloat(cos(a)) * hL * bubble.radius
            let y = surfaceY + CGFloat(sin(a)) * hL * k * bubble.radius + tilt * (x - cx) / max(hL, 1)
            let s = bubble.size * u
            context.fill(Path(ellipseIn: CGRect(x: x - s, y: y - s * 0.72, width: s * 2, height: s * 1.44)), with: .color(Palette.crema.color(0.95)))
            context.fill(Path(ellipseIn: CGRect(x: x - s * 0.5, y: y - s * 0.55, width: s * 0.7, height: s * 0.5)), with: .color(.white.opacity(0.5)))
        }
    }

    /// The thick glass foot, visible only below the floor so it never washes over the coffee.
    private func paintBase(in context: inout GraphicsContext) {
        var slab = Path()
        append(outline(from: 0, to: base, radius: outer, phis: 0...Double.pi), to: &slab)
        append(arcPoints(center: center(base), r: inner(base), from: .pi, to: 0), to: &slab)
        slab.closeSubpath()
        context.fill(slab, with: .color(.white.opacity(0.06)))
        if frame.level > 0.01 {
            context.fill(
                slab,
                with: .linearGradient(
                    Gradient(colors: [Palette.amber.color(0.36 * frame.level), Palette.coffeeEdge.color(0.1 * frame.level)]),
                    startPoint: CGPoint(x: cx, y: yb - base),
                    endPoint: CGPoint(x: cx, y: yb + outer(0) * k)
                )
            )
        }
        context.stroke(arc(center: center(base), r: inner(base), from: 0.05, to: .pi - 0.05), with: .color(.white.opacity(0.28)), lineWidth: 0.8 * u)
        context.stroke(arc(center: center(base * 0.5), r: outer(base * 0.5) - 2.5 * u, from: 0.3, to: .pi - 0.3), with: .color(.white.opacity(0.1)), lineWidth: 0.7 * u)
    }

    private func paintHandle(in context: inout GraphicsContext) {
        let top = height * 0.8
        let bottom = height * 0.3
        let a = CGPoint(x: cx + outer(top) + 1 * u, y: yb - top)
        let b = CGPoint(x: cx + outer(bottom) + 0.5 * u, y: yb - bottom)
        var spine = Path()
        spine.move(to: a)
        spine.addCurve(
            to: b,
            control1: CGPoint(x: a.x + 31 * u, y: a.y - 3 * u),
            control2: CGPoint(x: b.x + 27 * u, y: b.y + 9 * u)
        )
        let rod = spine.strokedPath(StrokeStyle(lineWidth: 6.5 * u, lineCap: .round))
        context.fill(rod, with: .color(.white.opacity(0.075)))
        context.stroke(rod, with: .color(.white.opacity(0.34)), lineWidth: 0.8 * u)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.7 * u))
            layer.translateBy(x: -0.6 * u, y: -1.3 * u)
            layer.stroke(spine, with: .color(.white.opacity(0.38)), lineWidth: 1.1 * u)
        }
    }

    private func paintCupFront(in context: inout GraphicsContext) {
        let front = outline(from: 0, to: height, radius: outer, phis: 0...Double.pi)
        var silhouette = Path()
        append(front, to: &silhouette)
        context.stroke(
            silhouette,
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0.5), .white.opacity(0.38)]),
                startPoint: CGPoint(x: cx, y: yb - height),
                endPoint: CGPoint(x: cx, y: yb + outer(0) * k)
            ),
            lineWidth: 1 * u
        )

        var innerWall = Path()
        append(outline(from: base, to: height, radius: inner, phis: 0...Double.pi), to: &innerWall)
        context.stroke(innerWall, with: .color(.white.opacity(0.1)), lineWidth: 0.7 * u)

        paintStreak(phi: .pi * 0.8, width: 4.6 * u, peak: 0.36, in: &context)
        paintStreak(phi: .pi * 0.17, width: 2.2 * u, peak: 0.16, in: &context)

        var lip = Path()
        lip.addPath(ellipse(center(height), rimR))
        lip.addPath(ellipse(center(height), rimR - wall))
        context.fill(lip, with: .color(.white.opacity(0.1)), style: FillStyle(eoFill: true))
        context.stroke(arc(center: center(height), r: rimR, from: 0, to: .pi), with: .color(.white.opacity(0.78)), lineWidth: 1.2 * u)
        context.stroke(arc(center: center(height), r: rimR - wall, from: 0.05, to: .pi - 0.05), with: .color(.white.opacity(0.3)), lineWidth: 0.7 * u)

        let glint = point(height, .pi * 0.76, rimR)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.4 * u))
            layer.fill(Path(ellipseIn: CGRect(x: glint.x - 5 * u, y: glint.y - 1.5 * u, width: 10 * u, height: 3 * u)), with: .color(.white.opacity(0.9)))
        }
        context.fill(Path(ellipseIn: CGRect(x: glint.x - 1.5 * u, y: glint.y - 0.8 * u, width: 3 * u, height: 1.6 * u)), with: .color(.white))
    }

    /// A vertical highlight that follows the cup's curvature, rounded corner included.
    private func paintStreak(phi: Double, width: CGFloat, peak: Double, in context: inout GraphicsContext) {
        var path = Path()
        append(stride(from: height * 0.9, through: height * 0.1, by: -1.5 * u).map { point($0, phi, outer($0) - 1.5 * u) }, to: &path)
        let shade = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(peak), location: 0.2),
                .init(color: .white.opacity(peak * 0.45), location: 0.75),
                .init(color: .white.opacity(0), location: 1),
            ]),
            startPoint: CGPoint(x: cx, y: yb - height * 0.9),
            endPoint: CGPoint(x: cx, y: yb - height * 0.1)
        )
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.2 * u))
            layer.stroke(path, with: shade, style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        context.stroke(path, with: shade, lineWidth: 0.8 * u)
    }

    private var streamX: CGFloat { cx - 6 * u }

    private func paintStream(_ stream: CupFrame.Stream, in context: inout GraphicsContext) {
        let surfaceY = yb - liquidHeight(frame.level)
        let top = CGFloat(stream.top) * surfaceY
        let bottom = CGFloat(stream.bottom) * surfaceY
        guard bottom - top > 0.5 else { return }

        let wTop = 5 * u * stream.thickness
        let wBottom = 3.3 * u * stream.thickness
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0...24 {
            let y = top + (bottom - top) * CGFloat(i) / 24
            let w = (wTop + (wBottom - wTop) * (y / max(surfaceY, 1))) / 2
            let wiggle = CGFloat(sin(Double(y / u) * 0.09 - t * 22)) * 0.35 * u
            left.append(CGPoint(x: streamX - w + wiggle, y: y))
            right.append(CGPoint(x: streamX + w + wiggle, y: y))
        }
        var path = Path()
        append(left, to: &path)
        append(right.reversed(), to: &path)
        path.closeSubpath()
        context.fill(
            path,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Palette.coffeeDeep.color(), location: 0),
                    .init(color: Palette.amber.color(0.95), location: 0.3),
                    .init(color: Palette.coffee.color(), location: 0.65),
                    .init(color: Palette.coffeeDeep.color(), location: 1),
                ]),
                startPoint: CGPoint(x: streamX - wTop / 2, y: 0),
                endPoint: CGPoint(x: streamX + wTop / 2, y: 0)
            )
        )
        var highlight = Path()
        append(left.map { CGPoint(x: $0.x + 1.1 * u, y: $0.y) }, to: &highlight)
        context.stroke(highlight, with: .color(.white.opacity(0.3)), lineWidth: 0.6 * u)
    }

    private func paintSteam(in context: inout GraphicsContext) {
        let startY = yb - liquidHeight(frame.level) - 2 * u
        let endY = 4 * u
        let rise = startY - endY
        let wisps: [(x: CGFloat, phase: Double, speed: Double, period: Double)] = [
            (-rimR * 0.36, 0.0, 1.0, 4.2),
            (rimR * 0.0, 2.1, 0.82, 5.1),
            (rimR * 0.34, 4.0, 1.12, 3.7),
        ]

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3 * u))
            for (i, wisp) in wisps.enumerated() {
                let path = wispPath(wisp, index: i, startY: startY, rise: rise)
                let breath = 0.6 + 0.4 * sin(t * 0.55 + Double(i) * 2.3)
                let stops: [Gradient.Stop] = (0...10).map { j in
                    let s = Double(j) / 10
                    let envelope = smoothstep(0, 0.14, s) * (1 - smoothstep(0.35, 1, s))
                    let flicker = 0.55 + 0.45 * sin((s * 1.6 - t / wisp.period) * 2 * .pi + wisp.phase)
                    return .init(color: Palette.steam.color(0.6 * envelope * flicker * breath * frame.steam), location: s)
                }
                layer.stroke(
                    path,
                    with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: cx, y: startY), endPoint: CGPoint(x: cx, y: endY)),
                    style: StrokeStyle(lineWidth: 5 * u, lineCap: .round)
                )
            }
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 9 * u))
            for (i, wisp) in wisps.enumerated() {
                layer.stroke(
                    wispPath(wisp, index: i, startY: startY, rise: rise),
                    with: .linearGradient(
                        Gradient(colors: [Palette.steam.color(0), Palette.steam.color(0.15 * frame.steam), Palette.steam.color(0)]),
                        startPoint: CGPoint(x: cx, y: startY),
                        endPoint: CGPoint(x: cx, y: endY)
                    ),
                    lineWidth: 13 * u
                )
            }
        }
    }

    private func wispPath(_ wisp: (x: CGFloat, phase: Double, speed: Double, period: Double), index: Int, startY: CGFloat, rise: CGFloat) -> Path {
        var path = Path()
        append((0...36).map { j in
            let s = Double(j) / 36
            let amplitude = (2.2 + 9.5 * s) * Double(u)
            let wave = sin(s * 2.4 * .pi * (1 + Double(index) * 0.15) - t * 1.7 * wisp.speed + wisp.phase)
            let sway = sin(t * 0.37 + Double(index) * 1.9) * 5 * s * s * Double(u)
            return CGPoint(x: cx + wisp.x + CGFloat(wave * amplitude + sway), y: startY - CGFloat(s) * rise)
        }, to: &path)
        return path
    }

    // MARK: Geometry

    private func center(_ h: CGFloat) -> CGPoint { CGPoint(x: cx, y: yb - h) }

    /// The silhouette of the cup between two heights. For each direction it keeps the cross-section that
    /// reaches furthest, which traces rounded corners and tapered walls exactly.
    private func outline(from h0: CGFloat, to h1: CGFloat, radius: (CGFloat) -> CGFloat, phis: ClosedRange<Double> = 0...(2 * Double.pi)) -> [CGPoint] {
        let steps = 120
        let samples = 56
        return (0...steps).map { i in
            let phi = phis.lowerBound + (phis.upperBound - phis.lowerBound) * Double(i) / Double(steps)
            let s = CGFloat(sin(phi))
            var bestH = h0
            var best = -CGFloat.infinity
            for j in 0...samples {
                let h = h0 + (h1 - h0) * CGFloat(j) / CGFloat(samples)
                let score = radius(h) * k - h * s
                if score > best { best = score; bestH = h }
            }
            return point(bestH, phi, radius(bestH))
        }
    }

    private func ellipse(_ center: CGPoint, _ r: CGFloat, ratio: CGFloat? = nil) -> Path {
        let ry = r * (ratio ?? k)
        return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - ry, width: r * 2, height: ry * 2))
    }

    /// Angle 0 is right, π/2 is the front, π is left.
    private func arcPoints(center: CGPoint, r: CGFloat, from a: Double, to b: Double) -> [CGPoint] {
        (0...48).map { i in
            let angle = a + (b - a) * Double(i) / 48
            return CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * k * CGFloat(sin(angle)))
        }
    }

    private func arc(center: CGPoint, r: CGFloat, from a: Double, to b: Double) -> Path {
        var path = Path()
        append(arcPoints(center: center, r: r, from: a, to: b), to: &path)
        return path
    }

    /// The liquid surface, sheared by `tilt` so the coffee can slosh.
    private func surfacePoints(_ y: CGFloat, _ r: CGFloat, _ tilt: CGFloat, from a: Double, to b: Double) -> [CGPoint] {
        (0...64).map { i in
            let angle = a + (b - a) * Double(i) / 64
            let x = cx + r * CGFloat(cos(angle))
            return CGPoint(x: x, y: y + r * k * CGFloat(sin(angle)) + tilt * (x - cx) / max(r, 1))
        }
    }

    private func closed(_ points: [CGPoint]) -> Path {
        var path = Path()
        append(points, to: &path)
        path.closeSubpath()
        return path
    }

    /// Continues the current subpath, so a shape built from several arcs fills as one region.
    private func append(_ points: [CGPoint], to path: inout Path) {
        for point in points {
            if path.isEmpty { path.move(to: point) } else { path.addLine(to: point) }
        }
    }
}

/// Radius of the cup's cross-section at height `h`: a gently flared wall that rolls into a flat base.
private func profile(_ h: CGFloat, _ height: CGFloat, _ top: CGFloat, _ waist: CGFloat, _ corner: CGFloat) -> CGFloat {
    let h = max(0, h)
    if h >= corner { return waist + (top - waist) * (h - corner) / max(height - corner, 1) }
    let d = corner - h
    return waist - corner + (corner * corner - d * d).squareRoot()
}
