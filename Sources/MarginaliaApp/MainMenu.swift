import AppKit

enum MainMenu {
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Marginalia", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Marginalia", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Marginalia", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: #selector(DocumentWindowController.saveNow(_:)), keyEquivalent: "s")
        file.addItem(.separator())
        file.addItem(withTitle: "Reveal in Finder", action: #selector(DocumentWindowController.revealInFinder(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Copy Path", action: #selector(DocumentWindowController.copyPath(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Print…", action: #selector(DocumentWindowController.printDocument(_:)), keyEquivalent: "p")
        fileItem.submenu = file

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let find = NSMenu(title: "Find")
        let f1 = find.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f"); f1.tag = 1
        let f2 = find.addItem(withTitle: "Find Next", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "g"); f2.tag = 2
        let f3 = find.addItem(withTitle: "Find Previous", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "G"); f3.tag = 3
        let f4 = find.addItem(withTitle: "Use Selection for Find", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "E"); f4.tag = 7
        findItem.submenu = find
        edit.addItem(findItem)
        editItem.submenu = edit

        let formatItem = NSMenuItem(); main.addItem(formatItem)
        let format = NSMenu(title: "Format")
        format.addItem(withTitle: "Bold", action: #selector(EditorTextView.toggleBold(_:)), keyEquivalent: "b")
        format.addItem(withTitle: "Italic", action: #selector(EditorTextView.toggleItalic(_:)), keyEquivalent: "i")
        format.addItem(withTitle: "Code", action: #selector(EditorTextView.toggleCodeSpan(_:)), keyEquivalent: "e")
        format.addItem(withTitle: "Strikethrough", action: #selector(EditorTextView.toggleStrike(_:)), keyEquivalent: "")
        format.addItem(withTitle: "Link", action: #selector(EditorTextView.insertLink(_:)), keyEquivalent: "k")
        format.addItem(.separator())
        format.addItem(withTitle: "Raise Heading", action: #selector(EditorTextView.headingUp(_:)), keyEquivalent: "]").keyEquivalentModifierMask = [.command, .shift]
        format.addItem(withTitle: "Lower Heading", action: #selector(EditorTextView.headingDown(_:)), keyEquivalent: "[").keyEquivalentModifierMask = [.command, .shift]
        format.addItem(withTitle: "Toggle Task", action: #selector(EditorTextView.toggleTask(_:)), keyEquivalent: "\r")
        format.addItem(.separator())
        let mu = format.addItem(withTitle: "Move Line Up", action: #selector(EditorTextView.moveLineUp(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        mu.keyEquivalentModifierMask = [.option]
        let md = format.addItem(withTitle: "Move Line Down", action: #selector(EditorTextView.moveLineDown(_:)), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        md.keyEquivalentModifierMask = [.option]
        format.addItem(.separator())
        format.addItem(withTitle: "Add Comment", action: #selector(DocumentWindowController.addComment(_:)), keyEquivalent: "M")
        let ncm = format.addItem(withTitle: "Next Comment", action: #selector(DocumentWindowController.nextComment(_:)), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        ncm.keyEquivalentModifierMask = [.command, .option]
        let pcm = format.addItem(withTitle: "Previous Comment", action: #selector(DocumentWindowController.previousComment(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        pcm.keyEquivalentModifierMask = [.command, .option]
        format.addItem(withTitle: "Copy All Comments", action: #selector(DocumentWindowController.copyComments(_:)), keyEquivalent: "")
        formatItem.submenu = format

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Reading Mode", action: #selector(DocumentWindowController.toggleReading(_:)), keyEquivalent: "R")
        view.addItem(withTitle: "Next Theme", action: #selector(DocumentWindowController.cycleTheme(_:)), keyEquivalent: "T")
        view.addItem(.separator())
        let nc = view.addItem(withTitle: "Next Change", action: #selector(DocumentWindowController.nextChange(_:)), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        nc.keyEquivalentModifierMask = NSEvent.ModifierFlags.control
        let pc = view.addItem(withTitle: "Previous Change", action: #selector(DocumentWindowController.previousChange(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        pc.keyEquivalentModifierMask = NSEvent.ModifierFlags.control
        view.addItem(.separator())
        view.addItem(withTitle: "Bigger", action: #selector(DocumentWindowController.zoomIn(_:)), keyEquivalent: "+")
        view.addItem(withTitle: "Smaller", action: #selector(DocumentWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Actual Size", action: #selector(DocumentWindowController.zoomReset(_:)), keyEquivalent: "0")
        viewItem.submenu = view

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = window
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }
}
