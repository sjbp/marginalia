import AppKit

let version = "0.2.3"
let usage = """
usage: md [options] <file.md> [more.md ...]
  -w, --wait                                    block until the window closes (use as $EDITOR)
  -                                             read stdin into a new file in ~/Library/Application Support/Marginalia
  --screenshot <out.png> [--light|--dark] [--reading] [--line N]   render offscreen and exit
  --perf                                        print timings and exit
  --version
"""

var args = Array(CommandLine.arguments.dropFirst())
if args.contains("--version") { print("md \(version)"); exit(0) }
if args.isEmpty || args.contains("-h") || args.contains("--help") { print(usage); exit(args.isEmpty ? 1 : 0) }

// The CLI lives at Marginalia.app/Contents/MacOS/md. Symlinks are resolved by dyld already.
let exe = Bundle.main.executableURL!.resolvingSymlinksInPath()
let appURL = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let appBinary = appURL.appendingPathComponent("Contents/MacOS/Marginalia")
guard FileManager.default.isExecutableFile(atPath: appBinary.path) else {
    fputs("md: cannot find Marginalia.app next to \(exe.path)\n", stderr); exit(1)
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func resolve(_ p: String) -> URL {
    URL(fileURLWithPath: (p as NSString).expandingTildeInPath, relativeTo: cwd).standardizedFileURL
}

// Direct exec for diagnostic modes so the caller gets stdout and the exit code.
if args.contains("--screenshot") || args.contains("--perf") || args.contains("--edit-script") {
    var out: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if a == "--screenshot" || a == "--edit-script", i + 1 < args.count { out += [a, resolve(args[i + 1]).path]; i += 2; continue }
        if a == "--line" || a == "--theme", i + 1 < args.count { out += [a, args[i + 1]]; i += 2; continue }
        out.append(a.hasPrefix("-") ? a : resolve(a).path)
        i += 1
    }
    let p = Process()
    p.executableURL = appBinary
    p.arguments = out
    try! p.run()
    p.waitUntilExit()
    exit(p.terminationStatus)
}

var files: [URL] = []
var wait = false
var k = 0
while k < args.count {
    let a = args[k]
    if a == "--line" || a == "--theme" { k += 2; continue }
    if a == "-w" || a == "--wait" { wait = true; k += 1; continue }
    if a == "-" {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Marginalia/stdin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = dir.appendingPathComponent("stdin-\(f.string(from: Date())).md")
        try? data.write(to: url)
        files.append(url)
        k += 1; continue
    }
    if !a.hasPrefix("-") { files.append(resolve(a)) }
    k += 1
}
if files.isEmpty { print(usage); exit(1) }
for f in files where !FileManager.default.fileExists(atPath: f.path) {
    FileManager.default.createFile(atPath: f.path, contents: Data())
}
let cfg = NSWorkspace.OpenConfiguration()
cfg.activates = true
// If another copy of Marginalia is already running (a stale build, or the version that was replaced by a DMG
// upgrade), Launch Services would hand the files to it instead of starting the one we point at. Retire it first.
let bundleID = "com.sjbp.marginalia"
let wantedPath = appURL.standardizedFileURL.path
let wantedVersion = Bundle(url: appURL)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
let stale = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { running in
    guard let u = running.bundleURL else { return false }
    let samePlace = u.standardizedFileURL.path == wantedPath
    let runningVersion = Bundle(url: u)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    return !samePlace || runningVersion != wantedVersion
}
if !stale.isEmpty {
    for app in stale { app.terminate() }   // polite quit: windows autosave on close
    let deadline = Date().addingTimeInterval(4)
    while stale.contains(where: { !$0.isTerminated }) && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    for app in stale where !app.isTerminated { app.forceTerminate() }
    fputs("md: replaced a running copy of Marginalia with \(appURL.path)\n", stderr)
}

var remaining = Set(files.map { $0.standardizedFileURL.path })
if wait {
    // The app posts one notification per closed window with the file path; the CLI returns when all of its files are closed.
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.sjbp.marginalia.windowClosed"), object: nil, queue: .main) { n in
        if let p = n.userInfo?["path"] as? String { remaining.remove(p) }
        if remaining.isEmpty { exit(0) }
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
        if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == "com.sjbp.marginalia" { exit(0) }
    }
}
NSWorkspace.shared.open(files, withApplicationAt: appURL, configuration: cfg) { _, error in
    if let error { fputs("md: \(error.localizedDescription)\n", stderr); exit(1) }
    if !wait { exit(0) }
}
RunLoop.main.run()
