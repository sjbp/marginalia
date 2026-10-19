import AppKit

enum FontLoader {
    static var loaded = false

    static func registerBundledFonts() {
        guard !loaded else { return }
        loaded = true
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Fonts")) }
        if let env = ProcessInfo.processInfo.environment["MARGINALIA_RESOURCES"] {
            dirs.append(URL(fileURLWithPath: env).appendingPathComponent("Fonts"))
        }
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let ttfs = files.filter { $0.pathExtension.lowercased() == "ttf" } as CFArray
            CTFontManagerRegisterFontURLs(ttfs, .process, true) { errors, done in
                if CFArrayGetCount(errors) > 0 { NSLog("font registration errors: \(errors)") }
                return true
            }
            if files.contains(where: { $0.pathExtension == "ttf" }) { return }
        }
    }
}
