import AppKit

enum FontLoader {
    static var loaded = false
    static var registerMs: Double = 0

    /// Registers the chrome font and the current theme's fonts now, everything else after launch.
    static func registerBundledFonts(theme: ThemeSpec) {
        guard !loaded else { return }
        loaded = true
        let t0 = CFAbsoluteTimeGetCurrent()
        let needed = Set(["GoogleSansFlex"] + fileStems(for: theme))
        register { name in needed.contains(where: { name.hasPrefix($0) }) }
        registerMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        DispatchQueue.main.async { register { name in !needed.contains(where: { name.hasPrefix($0) }) } }
    }

    static func fileStems(for theme: ThemeSpec) -> [String] {
        switch theme.id {
        case "newsreader": return ["Newsreader", "GeistMono"]
        case "quattro": return ["iAWriterQuattroV", "iAWriterMonoV"]
        default: return ["GoogleSansFlex", "GoogleSansCode"]
        }
    }

    private static func register(_ include: (String) -> Bool) {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Fonts")) }
        if let env = ProcessInfo.processInfo.environment["MARGINALIA_RESOURCES"] {
            dirs.append(URL(fileURLWithPath: env).appendingPathComponent("Fonts"))
        }
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let ttfs = files.filter { $0.pathExtension.lowercased() == "ttf" && include($0.deletingPathExtension().lastPathComponent) }
            guard !ttfs.isEmpty else { if files.contains(where: { $0.pathExtension == "ttf" }) { return } else { continue } }
            CTFontManagerRegisterFontURLs(ttfs as CFArray, .process, true) { errors, done in
                if CFArrayGetCount(errors) > 0 { NSLog("font registration errors: \(errors)") }
                return true
            }
            return
        }
    }
}
