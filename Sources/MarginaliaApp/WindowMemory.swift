import AppKit

/// Per-file window frame and first visible character, in UserDefaults, LRU capped.
enum WindowMemory {
    struct Entry { var frame: NSRect; var offset: Int }
    private static let key = "windows"
    private static let cap = 200

    static func entry(for path: String) -> Entry? {
        guard let all = UserDefaults.standard.dictionary(forKey: key), let d = all[path] as? [String: Any],
              let x = d["x"] as? Double, let y = d["y"] as? Double, let w = d["w"] as? Double, let h = d["h"] as? Double else { return nil }
        return Entry(frame: NSRect(x: x, y: y, width: w, height: h), offset: d["o"] as? Int ?? 0)
    }

    static func store(_ e: Entry, for path: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[path] = ["x": e.frame.origin.x, "y": e.frame.origin.y, "w": e.frame.width, "h": e.frame.height, "o": e.offset, "t": Date().timeIntervalSince1970]
        if all.count > cap {
            let sorted = all.sorted { (($0.value as? [String: Any])?["t"] as? Double ?? 0) < (($1.value as? [String: Any])?["t"] as? Double ?? 0) }
            for (k, _) in sorted.prefix(all.count - cap) { all.removeValue(forKey: k) }
        }
        UserDefaults.standard.set(all, forKey: key)
    }
}
