#!/bin/bash
# Build a shareable disk image: Marginalia.app, an Applications shortcut, a Terminal-command installer, and a read-me.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT/Resources/Info.plist")
STAGE="$ROOT/_build/dmg"
OUT="$ROOT/_build/Marginalia-$VERSION.dmg"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp -R "$ROOT/_build/Marginalia.app" "$STAGE/Marginalia.app"
ln -s /Applications "$STAGE/Applications"

# The command installer only creates a symlink. It changes nothing else on the recipient's machine.
cat > "$STAGE/Install Terminal Command.command" <<'SH'
#!/bin/bash
set -e
APP="/Applications/Marginalia.app"
if [ ! -d "$APP" ]; then
  echo "Drag Marginalia to Applications first, then run this again."
  read -r -p "Press Return to close."
  exit 1
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$APP/Contents/MacOS/md" "$HOME/.local/bin/md"
echo "Installed: ~/.local/bin/md"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) echo "Try:  md ~/Desktop/notes.md" ;;
  *) echo "Add this line to your ~/.zshrc, then open a new terminal:"
     echo '  export PATH="$HOME/.local/bin:$PATH"' ;;
esac
read -r -p "Press Return to close."
SH
chmod +x "$STAGE/Install Terminal Command.command"

cat > "$STAGE/Read me.txt" <<TXT
Marginalia $VERSION

1. Drag Marginalia to Applications.
2. First launch is refused once because the app is not notarized with Apple.
   Open System Settings > Privacy & Security, scroll down, click "Open Anyway",
   then open the app again. On macOS 14 and earlier, right-click the app and choose Open.
3. Optional: double-click "Install Terminal Command" to get the md command,
   so "md notes.md" opens a file from any terminal.

Requires macOS 14 or later. Source and documentation: https://github.com/sjbp/marginalia
TXT

hdiutil create -volname "Marginalia" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
echo "$OUT"
