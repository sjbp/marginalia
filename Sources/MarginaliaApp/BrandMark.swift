import AppKit

/// The Marginalia mark, drawn in code so the app never ships a raster copy of it: three text strokes, the column
/// edge, a connector, and one note in the margin. Same geometry as Scripts/make-icon.py.
enum BrandMark {
    static func draw(in r: NSRect, ink: NSColor, note: NSColor, rule: NSColor? = nil) {
        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat, _ c: NSColor) {
            c.setFill()
            NSBezierPath(roundedRect: NSRect(x: r.minX + x * r.width, y: r.minY + y * r.height, width: w * r.width, height: h * r.height), xRadius: rad * r.width, yRadius: rad * r.height).fill()
        }
        let ruleColor = rule ?? ink.withAlphaComponent(0.55)
        for (x, y, w, h) in [(0.21, 0.330, 0.34, 0.052), (0.21, 0.474, 0.27, 0.052), (0.21, 0.618, 0.31, 0.052)] { rr(x, y, w, h, h / 2, ink) }
        rr(0.604, 0.285, 0.012, 0.430, 0.006, ruleColor)
        rr(0.622, 0.494, 0.055, 0.012, 0.006, ruleColor)
        rr(0.683, 0.432, 0.118, 0.136, 0.03, note)
    }
}
