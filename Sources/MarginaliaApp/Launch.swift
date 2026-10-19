import AppKit

/// Command line options the app binary understands when exec'd directly (by `md`).
struct LaunchOptions {
    var files: [URL] = []
    var screenshot: URL? = nil
    var perf = false
    var dark = false
    var reading = false

    static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--screenshot": if let p = it.next() { o.screenshot = URL(fileURLWithPath: p) }
            case "--perf": o.perf = true
            case "--dark": o.dark = true
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
