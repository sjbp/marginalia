<img src="Resources/brand/mark.svg" width="64" alt="">

# Marginalia

A native Mac app for reviewing Markdown with your AI. You don't need a full editor to read what Claude Code or Codex just wrote and talk back.

**Fast.** Opens a file in about 170 ms, a 1 MB file in 250 ms. When the agent edits the file on disk, the window repaints in under 50 ms, marks what changed, and keeps your place. Swift, AppKit, TextKit 2. No web view.

**Beautiful.** Rendered text by default, set in Geist on a 68-character measure with real margins. Tables and images render natively, code sits in quiet panels, nothing shouts. Light and dark.

**Built for the loop.** Select text, leave a comment, and it lands in the file as CriticMarkup next to the words it is about, so the agent reads it with a plain `cat`. Replies thread. The agent's own edits show up as change bars. The file on disk is the only source of truth; there is no database and nothing to sync.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Resources/readme/dark.png">
  <img src="Resources/readme/light.png" alt="Marginalia showing a rendered Markdown file with a comment thread in the margin" width="100%">
</picture>

## Use

    md notes.md            # open; creates the file if it is new, focuses the window if it is already open
    md -w notes.md         # block until the window closes, so it works as $EDITOR
    echo "# Draft" | md -  # stdin into a new file

Comments look like this in the file, which is all the agent needs to see:

    {==the words being discussed==}{>>@you: tighten this<<}{>>@claude: done, see below<<}

## Install

Download the DMG from the [latest release](https://github.com/sjbp/marginalia/releases/latest) and drag Marginalia to Applications. The app is signed but not notarized with Apple, so the first launch is refused once: open System Settings → Privacy & Security, scroll down, and click **Open Anyway** (on macOS 14 and earlier, right-click the app and choose Open). Then double-click "Install Terminal Command" inside the DMG to get `md`. Or build it yourself on macOS 14 or later with the Xcode command line tools:

    make install

## Keys

⌘K palette · ⌘O open recent · ⌘⇧M comment · ⌘⇧R show Markdown · ⌘B ⌘I ⌘E ⌘⇧K bold italic code link · ⌘1 ⌘2 ⌘3 headings · ⌘⇧8 ⌘⇧7 ⌘⇧9 lists · ⌘⏎ toggle task · ⌥⌘↓ next comment · ⌃↓ next change

## Development

`make run`, `make test`, `make edit-test`, `make overlay-test`, `make publish VERSION=x.y.z`. See `ARCHITECTURE.md`, `RELEASING.md`, and `DECISIONS.md`.

MIT. Fonts are SIL OFL, bundled with their licenses.
