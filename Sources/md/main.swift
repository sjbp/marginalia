import AppKit

let version = "0.1.0"
let usage = """
usage: md [options] <file.md> [more.md ...]
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
if args.contains("--screenshot") || args.contains("--perf") {
    var out: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if a == "--screenshot", i + 1 < args.count { out += [a, resolve(args[i + 1]).path]; i += 2; continue }
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
var k = 0
while k < args.count {
    let a = args[k]
    if a == "--line" || a == "--theme" { k += 2; continue }
    if !a.hasPrefix("-") { files.append(resolve(a)) }
    k += 1
}
for f in files where !FileManager.default.fileExists(atPath: f.path) {
    FileManager.default.createFile(atPath: f.path, contents: Data())
}
let cfg = NSWorkspace.OpenConfiguration()
cfg.activates = true
NSWorkspace.shared.open(files, withApplicationAt: appURL, configuration: cfg) { _, error in
    if let error { fputs("md: \(error.localizedDescription)\n", stderr); exit(1) }
    exit(0)
}
RunLoop.main.run()
