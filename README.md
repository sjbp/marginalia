# Marginalia

A fast, native macOS workbench for reading, editing, and annotating Markdown files, built for the human half of a loop with an AI agent that writes files from the terminal.

Claude writes or edits a `.md` file. Marginalia, already open on it, repaints in under 50 ms and marks what changed. You read styled text, drop a comment in the margin, maybe fix a sentence. Comments are saved inside the file as CriticMarkup, so the agent reads them with a plain `cat`. Repeat.

- Opens in about 170 ms, 1 MB files in about 250 ms. Swift 6, AppKit, TextKit 2, no web view.
- Rendered text by default, fully editable; a Text | Markdown switch in the corner shows the source.
- Margin comments as threaded cards: `{==anchor==}{>>@sebo: note<<}{>>@claude: reply<<}`.
- External edits merge three ways when you were mid-edit, with caret and scroll preserved.
- Geist and Geist Mono by default; Google Sans Flex, Newsreader, and iA Writer Quattro as alternates. All fonts are SIL OFL and bundled.

## Install

Requires macOS 14 and Xcode 16 command line tools. Nothing is installed globally.

    make install        # release build → /Applications/Marginalia.app, symlink ~/.local/bin/md

## Use

    md notes.md                 # open (creates the file if missing); focuses the window if already open
    md -w notes.md              # block until the window closes (works as $EDITOR)
    echo "# Draft" | md -       # stdin into a new file

| Keys | Action |
|---|---|
| ⌘K | Command palette (`#` prefix jumps to headings) |
| ⌘O / ⌘⇧O | Quick open recents and siblings / outline |
| ⌘⇧R | Show Markdown / back to rendered text |
| ⌘⇧M | Comment on the selection (also in the format bar that appears on selection) |
| ⌥⌘↓ ⌥⌘↑ | Next / previous comment |
| ⌃↓ ⌃↑ | Next / previous change after an external update |
| ⌘B ⌘I ⌘E ⌘⇧K | Bold, italic, code, link |
| ⌘1 ⌘2 ⌘3 ⌥⌘0 | Heading 1, 2, 3, paragraph |
| ⌘⇧8 ⌘⇧7 ⌘⇧9 ⌘⇧. | Bulleted, numbered, task list, quote |
| ⌘⏎ | Toggle task (or click the checkbox) |
| ⌘⇧T | Next theme |

## Develop

    make run            # debug build, bundle, open Fixtures/tour.md
    make test           # Core unit tests
    make edit-test      # scripted editing session, byte-exact
    make overlay-test   # real key events; tables, images and comment cards must stay on their lines
    make smoke          # screenshots into _build/smoke/

The app can drive itself headlessly: `md --screenshot out.png file.md`, `md --perf file.md`, and `md --edit-script script.txt file.md` (see `Sources/MarginaliaApp/EditScript.swift`). Everything builds from the terminal; Xcode is not opened.

Read `HANDOFF.md` for status, perf numbers, and known issues, `DECISIONS.md` for every deviation from `SPEC.md` and why, and `SPEC.md` for the original design.

## Layout

    Sources/MarginaliaCore   parser (swift-markdown + UTF-8→UTF-16 source map), CriticMarkup, smart-edit rules, line diff and three-way merge
    Sources/MarginaliaApp    AppKit app: window controller, styler, editor view, comment margin, overlays, palette, settings
    Sources/md               the CLI; finds the app relative to its own binary
    Fixtures                 tour.md and the scripted regression flows
    Resources/Fonts          bundled OFL fonts with their license files

## License

Source: MIT. Bundled typefaces: SIL Open Font License, see `Resources/Fonts/OFL-*.txt`.
