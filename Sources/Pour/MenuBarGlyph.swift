import AppKit

/// The status item icon. A template image, so the menu bar tints it for light, dark, and tinted bars.
enum MenuBarGlyph {
    static func image(level: Double, steam: Double, time: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.setStrokeColor(NSColor.black.cgColor)
            cg.setFillColor(NSColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let body = CGRect(x: 3.6, y: 6.4, width: 10.2, height: 8.2)
            let mug = roundedBottom(body, radius: 3)
            cg.setLineWidth(1.35)
            cg.addPath(mug)
            cg.strokePath()

            cg.addPath(handle(from: body))
            cg.strokePath()

            cg.move(to: CGPoint(x: 1.9, y: 16.9))
            cg.addLine(to: CGPoint(x: 15.5, y: 16.9))
            cg.strokePath()

            if level > 0.001 {
                let inner = body.insetBy(dx: 1.75, dy: 1.75)
                let height = inner.height * CGFloat(level)
                cg.saveGState()
                cg.addPath(roundedBottom(inner, radius: 1.5))
                cg.clip()
                cg.fill(CGRect(x: inner.minX, y: inner.maxY - height, width: inner.width, height: height))
                cg.restoreGState()
            }

            if steam > 0.01 {
                cg.setLineWidth(1.15)
                for (i, x) in [6.9, 10.4].enumerated() {
                    let phase = time * 2.4 + Double(i) * 2.1
                    let bend = 1.25 * (0.7 + 0.3 * sin(phase))
                    let drift = 0.35 * sin(phase * 0.5)
                    let wisp = CGMutablePath()
                    wisp.move(to: CGPoint(x: x, y: 5.3))
                    wisp.addCurve(
                        to: CGPoint(x: x + drift, y: 0.6),
                        control1: CGPoint(x: x - bend, y: 3.9),
                        control2: CGPoint(x: x + bend + drift, y: 2.1)
                    )
                    let breath = 0.7 + 0.3 * sin(time * 1.4 + Double(i) * 2.2)
                    cg.setAlpha(CGFloat(steam * breath))
                    cg.addPath(wisp)
                    cg.strokePath()
                }
                cg.setAlpha(1)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func roundedBottom(_ r: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.maxY), control: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - radius), control: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return path
    }

    private static func handle(from body: CGRect) -> CGPath {
        let path = CGMutablePath()
        let top = body.minY + 1.9
        let bottom = body.maxY - 2.6
        path.move(to: CGPoint(x: body.maxX, y: top))
        path.addCurve(
            to: CGPoint(x: body.maxX, y: bottom),
            control1: CGPoint(x: body.maxX + 3.6, y: top - 0.2),
            control2: CGPoint(x: body.maxX + 3.6, y: bottom + 0.4)
        )
        return path
    }
}
