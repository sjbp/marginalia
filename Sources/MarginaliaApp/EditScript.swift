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
        let um = wc.textView.undoManager
        um?.groupsByEvent = false
        func step() {
            guard i < lines.count else { return completion() }
            let line = lines[i]; i += 1
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let cmd = parts.first ?? ""
            let arg = parts.count > 1 ? parts[1] : ""
            let tv = wc.textView
            let isUndo = cmd == "key" && (arg == "undo" || arg == "redo")
            if !isUndo { um?.beginUndoGrouping() }
            defer { if !isUndo { um?.endUndoGrouping() } }
            switch cmd {
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
                case "undo": tv.breakUndoCoalescing(); tv.undoManager?.undo()
                case "redo": tv.undoManager?.redo()
                default: break
                }
            case "action":
                NSApp.sendAction(Selector(arg + ":"), to: tv, from: nil)
            case "save":
                wc.saveNow(nil)
            case "sleep":
                let ms = Double(arg) ?? 100
                DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000) { step() }
                return
            case "debug":
                let um = tv.undoManager
                fputs("debug: text=\(tv.string.debugDescription) sel=\(tv.selectedRange()) canUndo=\(um?.canUndo ?? false) level=\(um?.groupingLevel ?? -1) umIsWindow=\(um === wc.window?.undoManager)\n", stderr)
            case "#": break
            default: fputs("edit-script: unknown command \(line)\n", stderr)
            }
            // Yield a real run-loop turn so undo groups close like they do between keystrokes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { step() }
        }
        step()
    }
}
