import AppKit
import MarginaliaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var options = LaunchOptions()
    var windows: [DocumentWindowController] = []
    private var openedViaLaunchServices = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        ProcessClock.mark("willFinishLaunching")
        options = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
        if options.dark { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if options.light { NSApp.appearance = NSAppearance(named: .aqua) }
        FontLoader.registerBundledFonts(theme: ThemeSpec.named(options.theme ?? UserDefaults.standard.string(forKey: "theme") ?? "flex"))
        if CommandLine.arguments.contains("--fonts") { FontDebug.dump(); exit(0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessClock.mark("didFinishLaunching")
        for url in options.files { open(url) }
        ProcessClock.mark("windowsOpened")
        // The menu is only needed once the user reaches for it; install it after the first paint.
        DispatchQueue.main.async { MainMenu.install(); ProcessClock.mark("menuInstalled") }
        if let scriptPath = options.editScript, let wc = windows.last {
            let script = (try? String(contentsOfFile: scriptPath, encoding: .utf8)) ?? ""
            EditScript.run(script, in: wc) { wc.saveNow(nil); exit(0) }
            return
        }
        if let shot = options.screenshot {
            guard let wc = windows.last else { fputs("nothing to screenshot\n", stderr); exit(1) }
            let line = options.scrollToLine
            Screenshot.capture(window: wc.window!, to: shot, afterLayout: line.map { l in { wc.scroll(toLine: l) } }) { ok in
                if self.options.perf { wc.printPerf() }
                exit(ok ? 0 : 1)
            }
        } else if options.perf {
            guard let wc = windows.last else { exit(1) }
            DispatchQueue.main.async {
                wc.window?.displayIfNeeded()
                wc.printPerf()
                exit(0)
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedViaLaunchServices = true
        for url in urls { open(url) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let d = UserDefaults.standard
        return d.object(forKey: "keepRunning") != nil && !d.bool(forKey: "keepRunning")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDocument(nil) }
        return true
    }

    @discardableResult
    func open(_ url: URL) -> DocumentWindowController? {
        let path = url.standardizedFileURL.path
        if let existing = windows.first(where: { $0.doc.url.path == path }) {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: Data())
        }
        do {
            let doc = try Document(url: url)
            let wc = DocumentWindowController(document: doc, sourceMode: options.source, themeOverride: options.theme)
            windows.append(wc)
            Recents.touch(url.standardizedFileURL)
            wc.onClose = { [weak self, weak wc] in self?.windows.removeAll { $0 === wc } }
            wc.showWindow(nil)
            return wc
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for w in windows { w.saveNow(nil); w.storeMemory() }
    }

    @objc func showSettings(_ sender: Any?) { SettingsWindowController.shared.show() }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md")!].compactMap { $0 }
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach { open($0) } }
    }
}
