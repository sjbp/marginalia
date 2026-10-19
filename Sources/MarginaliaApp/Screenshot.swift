import AppKit

enum Screenshot {
    /// Renders the window's content view to a PNG after layout settles. Works offscreen.
    static func capture(window: NSWindow, to url: URL, afterLayout: (() -> Void)? = nil, completion: @escaping (Bool) -> Void) {
        window.setContentSize(NSSize(width: 1400, height: 1000))
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
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return completion(false) }
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
