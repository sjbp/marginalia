import AppKit
import MarginaliaCore

/// Drives the editor from a text script so editing behavior can be verified headlessly.
/// One command per line:
///   select <loc> <len>      type <text>        key return|shift-return|tab|backtab|delete
///   action <selector>       save               sleep <ms>
enum EditScript {
    /// Every visible table/image overlay and comment card must sit on its text line. Ground truth is TextKit's position
    /// after a full layout from the document start; offsets come from the current text, never from a possibly stale model.
    static func assertOverlays(_ wc: DocumentWindowController, label: String, informational: Bool = false) {
        let tv = wc.textView
        guard let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return }
        let fresh = SourceMap(tv.string)
        let docStart = tcs.documentRange.location
        let originY = tv.textContainerOrigin.y
        func truthTop(_ offset: Int) -> CGFloat? {
            guard let loc = tcs.location(docStart, offsetBy: min(offset, fresh.utf16Count)) else { return nil }
            if let span = NSTextRange(location: docStart, end: loc) { tlm.ensureLayout(for: span) }
            var y: CGFloat? = nil
            tlm.enumerateTextLayoutFragments(from: loc, options: [.ensuresLayout]) { f in y = f.layoutFragmentFrame.minY; return false }
            return y.map { $0 + originY }
        }
        var fails = 0, checked = 0
        for (li, v) in wc.overlayViews where !v.isHidden && li < fresh.lineCount {
            checked += 1
            guard let t = truthTop(fresh.lineRange(li).location) else { continue }
            let delta = v.frame.minY - (t + 6)
            if abs(delta) > 2 { fails += 1; fputs("  OVERLAY MISPLACED line=\(li) frameY=\(Int(v.frame.minY)) expected=\(Int(t + 6)) delta=\(Int(delta))\n", stderr) }
        }
        for card in wc.margin.cards where !card.isHidden {
            checked += 1
            guard let t = truthTop(card.anchorLocation) else { continue }
            let delta = card.frame.minY - (t - 2)
            if delta < -2 { fails += 1; fputs("  CARD MISPLACED anchor=\(card.anchorLocation) frameY=\(Int(card.frame.minY)) lineTop=\(Int(t)) delta=\(Int(delta))\n", stderr) }
        }
        let verdict = fails == 0 ? "ASSERT_OVERLAYS PASS" : (informational ? "ASSERT_OVERLAYS transient" : "ASSERT_OVERLAYS FAIL")
        fputs(verdict + " \(label) (\(fails) of \(checked))\n", stderr)
    }

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
            case "keys":   // real key events through the window, one per character, like a person typing
                guard let w = wc.window else { break }
                var chars = Array(arg.replacingOccurrences(of: "\\n", with: "\n"))
                func next() {
                    guard !chars.isEmpty else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { step() }; return }
                    let ch = String(chars.removeFirst())
                    let code: UInt16 = ch == "\n" ? 36 : 0
                    let t = ProcessInfo.processInfo.systemUptime
                    if let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: t, windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code),
                       let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: t + 0.01, windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code) {
                        w.sendEvent(down); w.sendEvent(up)
                    }
                    // let the run loop draw between keystrokes, like real typing at ~60 wpm
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { next() }
                }
                next()
                return
            case "assert-overlays":   // every visible overlay and card must sit on its text line (tolerance 3 pt)
                assertOverlays(wc, label: "")
            case "keys!":   // like keys, but asserts overlay placement right after each key and again 30 ms later
                guard let w = wc.window else { break }
                var chars = Array(arg)
                var n = 0
                func next() {
                    guard !chars.isEmpty else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { step() }; return }
                    let ch = String(chars.removeFirst()); n += 1
                    if ProcessInfo.processInfo.environment["MARGINALIA_DEBUG"] != nil { fputs("key\(n) '\(ch)' caret=\(tv.selectedRange().location) firstResponder=\(String(describing: type(of: w.firstResponder)))\n", stderr) }
                    let t = ProcessInfo.processInfo.systemUptime
                    if let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: t, windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: 0),
                       let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: t + 0.01, windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: 0) {
                        w.sendEvent(down); w.sendEvent(up)
                    }
                    w.displayIfNeeded()
                    assertOverlays(wc, label: "key\(n) immediate (informational, one frame of TextKit estimation is tolerated)", informational: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { w.displayIfNeeded(); assertOverlays(wc, label: "key\(n) +30ms"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { next() } }
                }
                next()
                return
            case "assert-overlays-old":
                var fails = 0, checked = 0
                func lineTop(_ offset: Int) -> CGFloat? {
                    guard let top = wc.lineTop(ofOffset: offset) else { return nil }
                    // lineTop is in clip-view coords (== text view coords here since the text view fills the clip view)
                    return top
                }
                if let m = wc.model {
                    for (li, v) in wc.overlayViews where !v.isHidden {
                        checked += 1
                        let off = m.lines[li].range.location
                        guard let t = lineTop(off) else { continue }
                        let expected = t + 6
                        let delta = v.frame.minY - expected
                        if abs(delta) > 3 { fails += 1; fputs("OVERLAY MISPLACED line=\(li) frameY=\(Int(v.frame.minY)) expected=\(Int(expected)) delta=\(Int(delta))\n", stderr) }
                    }
                    for card in wc.margin.cards where !card.isHidden {
                        checked += 1
                        guard let t = lineTop(card.anchorLocation) else { continue }
                        // cards may be pushed down by a previous card, so only "too high" is a failure
                        let delta = card.frame.minY - (t - 2)
                        if delta < -3 { fails += 1; fputs("CARD MISPLACED anchor=\(card.anchorLocation) frameY=\(Int(card.frame.minY)) lineTop=\(Int(t)) delta=\(Int(delta))\n", stderr) }
                    }
                }
                fputs(fails == 0 ? "ASSERT_OVERLAYS PASS (\(checked) checked)\n" : "ASSERT_OVERLAYS FAIL (\(fails) of \(checked))\n", stderr)
            case "click":   // click <offset>: real mouse down/up at that character's on-screen position
                guard let w = wc.window, let off = Int(arg) else { break }
                // Bring the target on screen first (window memory may have restored another scroll position), then measure
                // from the offset to the end of its line: a single hidden marker character has no usable rect.
                tv.scrollRangeToVisible(NSRange(location: off, length: 0))
                w.displayIfNeeded()
                let lr = (tv.string as NSString).lineRange(for: NSRange(location: off, length: 0))
                let r = tv.firstRect(forCharacterRange: NSRange(location: off, length: max(1, lr.location + lr.length - off)), actualRange: nil)
                let inWindow = w.convertFromScreen(r)
                let p = NSPoint(x: inWindow.minX + 1, y: inWindow.midY)
                let t = ProcessInfo.processInfo.systemUptime
                if let d = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: t, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                   let u = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: t + 0.05, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) {
                    w.sendEvent(d); w.sendEvent(u)
                }
                if ProcessInfo.processInfo.environment["MARGINALIA_DEBUG"] != nil {
                    let tvInWindow = tv.convert(tv.bounds, to: nil)
                    fputs("click: screenRect=\(r) inWindow=\(inWindow) point=\(p) tvInWindow=\(tvInWindow) windowFrame=\(w.frame) hit=\(tv.characterIndexForInsertion(at: tv.convert(p, from: nil)))\n", stderr)
                }
                fputs("click at offset \(off) -> caret \(tv.selectedRange().location)\n", stderr)
            case "focus":
                NSApp.activate(ignoringOtherApps: true)
                wc.window?.makeKeyAndOrderFront(nil)
                wc.window?.makeFirstResponder(tv)
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
                case "delete-forward": tv.deleteForward(nil)
                case "left": tv.moveLeft(nil)
                case "right": tv.moveRight(nil)
                case "bar": tv.formatBar?.update(selection: tv.selectedRange())
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
                    switch parts[1] { case "reply": c.beginReply(); case "resolve": c.onResolve?(); default: c.onSelect?() }
                } else { fputs("edit-script: bad card command \(arg) (cards=\(wc.margin.cards.count))\n", stderr) }
            case "type-card":
                if let card = wc.margin.cards.first(where: { $0.isComposing }) { card.commitComposer(arg) }
                else { fputs("edit-script: no card is composing\n", stderr) }
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
