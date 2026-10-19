import AppKit

enum Screenshot {
    /// Renders the window's content view to a PNG after layout settles. Works offscreen.
    static func capture(window: NSWindow, to url: URL, afterLayout: (() -> Void)? = nil, completion: @escaping (Bool) -> Void) {
        // MARGINALIA_SHOT_SIZE=WxH overrides the window size; renders at 2x so README images stay crisp on Retina.
        var size = NSSize(width: 1400, height: 1000)
        if let spec = ProcessInfo.processInfo.environment["MARGINALIA_SHOT_SIZE"]?.split(separator: "x"), spec.count == 2,
           let w = Double(spec[0]), let h = Double(spec[1]) { size = NSSize(width: w, height: h) }
        window.setContentSize(size)
        window.center()
        window.orderFront(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        // Two turns of the run loop so TextKit 2 viewport layout and any async styling finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          afterLayout?()
          window.layoutIfNeeded(); window.displayIfNeeded()
          DispatchQueue.main.asyncAfter(deadline: .now() + (afterLayout == nil ? 0.05 : 0.2)) {
            guard let view = window.contentView else { return completion(false) }
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            let scale = max(2, window.backingScaleFactor)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale), pixelsHigh: Int(view.bounds.height * scale),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return completion(false) }
            rep.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return completion(false) }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: url)
                completion(true)
            } catch {
                fputs("screenshot failed: \(error)\n", stderr)
                completion(false)
            }
          }
        }
    }
}
