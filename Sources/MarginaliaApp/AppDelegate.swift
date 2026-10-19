import AppKit
import MarginaliaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var options = LaunchOptions()
    var windows: [DocumentWindowController] = []
    private var openedViaLaunchServices = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        options = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
        if options.dark { NSApp.appearance = NSAppearance(named: .darkAqua) }
        FontLoader.registerBundledFonts()
        MainMenu.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for url in options.files { open(url) }
        if let shot = options.screenshot {
            guard let wc = windows.last else { fputs("nothing to screenshot\n", stderr); exit(1) }
            Screenshot.capture(window: wc.window!, to: shot) { ok in
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
            let wc = DocumentWindowController(document: doc, reading: options.reading)
            windows.append(wc)
            wc.onClose = { [weak self, weak wc] in self?.windows.removeAll { $0 === wc } }
            wc.showWindow(nil)
            return wc
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md")!].compactMap { $0 }
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach { open($0) } }
    }
}
