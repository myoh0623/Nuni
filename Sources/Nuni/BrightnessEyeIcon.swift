import AppKit

enum BrightnessEyeIcon {
    static func image(brightness: Double) -> NSImage {
        let value = AdaptiveMath.clamp(brightness)
        let size = NSSize(width: 19, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

            if value <= 0.005 {
                drawClosedEye()
            } else {
                drawOpenEye(openness: pow(value, 0.72))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Brightness \(Int((value * 100).rounded())) percent"
        return image
    }

    private static func drawClosedEye() {
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: 2.2, y: 10.2))
        lid.curve(
            to: NSPoint(x: 16.8, y: 10.2),
            controlPoint1: NSPoint(x: 6.1, y: 6.8),
            controlPoint2: NSPoint(x: 12.9, y: 6.8)
        )
        lid.lineWidth = 1.8
        lid.lineCapStyle = .round
        lid.stroke()

        for x in [5.1, 9.5, 13.9] {
            let lash = NSBezierPath()
            lash.move(to: NSPoint(x: x, y: 7.9))
            lash.line(to: NSPoint(x: x, y: 6.5))
            lash.lineWidth = 1.2
            lash.lineCapStyle = .round
            lash.stroke()
        }
    }

    private static func drawOpenEye(openness: Double) {
        let centerY = 9.2
        let halfHeight = 1.0 + 5.2 * openness
        let left = NSPoint(x: 1.6, y: centerY)
        let right = NSPoint(x: 17.4, y: centerY)

        let outline = NSBezierPath()
        outline.move(to: left)
        outline.curve(
            to: right,
            controlPoint1: NSPoint(x: 5.3, y: centerY + halfHeight),
            controlPoint2: NSPoint(x: 13.7, y: centerY + halfHeight)
        )
        outline.curve(
            to: left,
            controlPoint1: NSPoint(x: 13.7, y: centerY - halfHeight),
            controlPoint2: NSPoint(x: 5.3, y: centerY - halfHeight)
        )
        outline.close()
        outline.lineWidth = 1.45
        outline.lineJoinStyle = .round
        outline.stroke()

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let irisRadius = min(3.15, 0.7 + 2.7 * openness)
        NSBezierPath(
            ovalIn: NSRect(
                x: 9.5 - irisRadius,
                y: centerY - irisRadius,
                width: irisRadius * 2,
                height: irisRadius * 2
            )
        ).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
