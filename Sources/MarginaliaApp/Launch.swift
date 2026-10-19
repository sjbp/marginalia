import AppKit

/// Command line options the app binary understands when exec'd directly (by `md`).
struct LaunchOptions {
    var files: [URL] = []
    var screenshot: URL? = nil
    var perf = false
    var dark = false
    var light = false
    var reading = false
    var scrollToLine: Int? = nil
    var theme: String? = nil
    var editScript: String? = nil

    static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--screenshot": if let p = it.next() { o.screenshot = URL(fileURLWithPath: p) }
            case "--perf": o.perf = true
            case "--dark": o.dark = true
            case "--light": o.light = true
            case "--line": if let p = it.next(), let n = Int(p) { o.scrollToLine = n }
            case "--theme": o.theme = it.next()
            case "--edit-script": o.editScript = it.next()
            case "--reading": o.reading = true
            case _ where a.hasPrefix("-NS") || a.hasPrefix("-Apple"): _ = it.next() // AppKit debug flags
            case _ where a.hasPrefix("-"): break
            default: o.files.append(URL(fileURLWithPath: a).standardizedFileURL)
            }
        }
        return o
    }
}

enum ProcessClock {
    /// Set by the editor's first draw.
    static var firstPaintMs: Double = -1
    /// Milliseconds since the process was created, from the kernel, so dyld time counts.
    static func msSinceProcessStart() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return -1 }
        let start = info.kp_proc.p_starttime
        let startMs = Double(start.tv_sec) * 1000 + Double(start.tv_usec) / 1000
        var now = timeval()
        gettimeofday(&now, nil)
        let nowMs = Double(now.tv_sec) * 1000 + Double(now.tv_usec) / 1000
        return nowMs - startMs
    }
}

enum FontDebug {
    static func dump() {
        let wanted = ["Google Sans", "Newsreader", "Geist", "iA Writer"]
        for fam in NSFontManager.shared.availableFontFamilies where wanted.contains(where: { fam.contains($0) }) {
            print("family: \(fam)")
            for m in NSFontManager.shared.availableMembers(ofFontFamily: fam) ?? [] { print("   \(m[0]) / \(m[1])") }
            if let f = NSFont(name: (NSFontManager.shared.availableMembers(ofFontFamily: fam)?.first?[0] as? String) ?? fam, size: 12) {
                if let axes = CTFontCopyVariationAxes(f) as? [[String: Any]] {
                    for a in axes { print("   axis \(a[kCTFontVariationAxisNameKey as String] ?? "") id=\(a[kCTFontVariationAxisIdentifierKey as String] ?? "") min=\(a[kCTFontVariationAxisMinimumValueKey as String] ?? "") def=\(a[kCTFontVariationAxisDefaultValueKey as String] ?? "") max=\(a[kCTFontVariationAxisMaximumValueKey as String] ?? "")") }
                }
                if let feats = CTFontCopyFeatures(f) as? [[String: Any]] {
                    let names = feats.compactMap { $0[kCTFontOpenTypeFeatureTag as String] as? String ?? ($0[kCTFontFeatureTypeNameKey as String] as? String) }
                    print("   features: \(names.joined(separator: " "))")
                }
            }
        }
    }
}
