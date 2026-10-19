import AppKit
import MarginaliaCore

/// Drives the editor from a text script so editing behavior can be verified headlessly.
/// One command per line:
///   select <loc> <len>      type <text>        key return|shift-return|tab|backtab|delete
///   action <selector>       save               sleep <ms>
enum EditScript {
    static func run(_ script: String, in wc: DocumentWindowController, completion: @escaping () -> Void) {
        let lines = script.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var i = 0
        // No real events flow in script mode, so event-based undo grouping never closes. Group per step instead.
        if NSApp.mainMenu == nil { MainMenu.install() }
        let um = wc.textView.undoManager
        um?.groupsByEvent = false   // no real events; every mutation path opens its own group (see EditorTextView.perform)
        func step() {
            guard i < lines.count else { return completion() }
            let line = lines[i]; i += 1
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let cmd = parts.first ?? ""
            let arg = parts.count > 1 ? parts[1] : ""
            let tv = wc.textView
            let isUndo = cmd == "key" && (arg == "undo" || arg == "redo")
            if !isUndo { um?.beginUndoGrouping() }
            defer { if !isUndo, let um { while um.groupingLevel > 0 { um.endUndoGrouping() } } }
            switch cmd {
            case "resize":
                let nums = arg.split(separator: " ").compactMap { Double($0) }
                if nums.count == 2, let w = wc.window { w.setContentSize(NSSize(width: nums[0], height: nums[1])); w.center(); w.layoutIfNeeded() }
            case "select":
                let nums = arg.split(separator: " ").compactMap { Int($0) }
                tv.breakUndoCoalescing()
                if nums.count == 2 { tv.setSelectedRange(NSRange(location: nums[0], length: nums[1])) }
            case "type":
                tv.insertText(arg.replacingOccurrences(of: "\\n", with: "\n"), replacementRange: tv.selectedRange())
            case "key":
                switch arg {
                case "return": tv.insertNewline(nil)
                case "shift-return": tv.insertText("\n", replacementRange: tv.selectedRange())
                case "tab": tv.insertTab(nil)
                case "backtab": tv.insertBacktab(nil)
                case "delete": tv.deleteBackward(nil)
                case "undo": tv.breakUndoCoalescing(); um?.undo()
                case "redo": tv.undoManager?.redo()
                default: break
                }
            case "action":
                let sel = Selector(arg + ":")
                if tv.responds(to: sel) { NSApp.sendAction(sel, to: tv, from: nil) }
                else if wc.responds(to: sel) { NSApp.sendAction(sel, to: wc, from: nil) }
                else { fputs("edit-script: no responder for \(arg)\n", stderr) }
            case "card":   // card <index> reply|resolve|select
                let parts = arg.split(separator: " ").map(String.init)
                if parts.count == 2, let i = Int(parts[0]), i < wc.margin.cards.count {
                    let c = wc.margin.cards[i]
                    switch parts[1] { case "reply": c.onReply?(); case "resolve": c.onResolve?(); default: c.onSelect?() }
                } else { fputs("edit-script: bad card command \(arg) (cards=\(wc.margin.cards.count))\n", stderr) }
            case "type-card":
                if let card = wc.margin.cards.first(where: { $0.body.isEditable }) { card.body.stringValue = arg; card.endEditing(commit: true) }
                else { fputs("edit-script: no card is editing\n", stderr) }
            case "save":
                wc.saveNow(nil)
            case "scroll":
                if let n = Int(arg) { wc.scroll(toLine: n) }
            case "external-write":   // atomic replace, like Claude's Write tool
                try? Data(arg.replacingOccurrences(of: "\\n", with: "\n").utf8).write(to: wc.doc.url, options: .atomic)
            case "external-append":  // in-place append, like >>
                if let h = try? FileHandle(forWritingTo: wc.doc.url) { h.seekToEndOfFile(); h.write(Data(arg.replacingOccurrences(of: "\\n", with: "\n").utf8)); try? h.close() }
            case "external-file":    // replace with another file's content, atomically
                if let d = try? Data(contentsOf: URL(fileURLWithPath: arg)) { try? d.write(to: wc.doc.url, options: .atomic) }
            case "palette":   // palette <mode> [query]
                let parts = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if let w = wc.window { wc.palette.show(mode: parts.first ?? ">", in: w) }
                if parts.count > 1 { wc.palette.scriptType(parts[1]) }
            case "screenshot-palette":
                if let v = wc.palette.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg))
                }
            case "screenshot":
                if let w = wc.window {
                    Screenshot.capture(window: w, to: URL(fileURLWithPath: arg)) { _ in step() }
                    return
                }
            case "sleep":
                let ms = Double(arg) ?? 100
                DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000) { step() }
                return
            case "debug":
                let um = tv.undoManager
                let t = tv.string
                let head = t.count > 60 ? String(t.prefix(60)).debugDescription : t.debugDescription
                let fv = wc.firstVisible()
                let topLine = wc.model.map { $0.map.lineIndex(forUTF16: fv.offset) } ?? -1
                let topText = (tv.string as NSString).substring(with: NSRange(location: fv.offset, length: min(24, tv.string.utf16.count - fv.offset))).debugDescription
                fputs("debug: topLine=\(topLine) top=\(topText) delta=\(Int(fv.delta)) len=\(t.utf16.count) lines=\(t.split(separator: "\n", omittingEmptySubsequences: false).count) sel=\(tv.selectedRange()) marks=\(wc.changeMarks.count) visibleTop=\(Int(wc.scrollView.contentView.bounds.minY)) canUndo=\(um?.canUndo ?? false) head=\(head)\n", stderr)
            case "#": break
            default: fputs("edit-script: unknown command \(line)\n", stderr)
            }
            // Yield a real run-loop turn so undo groups close like they do between keystrokes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { step() }
        }
        step()
    }
}
