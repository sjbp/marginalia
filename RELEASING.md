# Releasing

Everything runs from the terminal. One command does the whole cycle once the version is decided:

    make publish VERSION=0.3.0

What it does, in order, stopping at the first failure:

1. Requires a clean working tree.
2. Writes the version into `Resources/Info.plist`.
3. Runs `swift test`, `make edit-test`, `make overlay-test`.
4. Builds the release bundle and the disk image (`make dmg`), copies the DMG to `~/Downloads`.
5. Commits `Release <version>`, tags `v<version>`, pushes branch and tag.
6. Creates the GitHub release with the DMG attached, using the top section of `CHANGELOG.md` as notes.

Before running it, add a section to `CHANGELOG.md` headed `## <version>` with what changed, written for the person installing it.

## Pieces, if you need them separately

    make dmg                       # release build + Marginalia-<version>.dmg in _build and ~/Downloads
    gh release create v0.2.0 ~/Downloads/Marginalia-0.2.0.dmg --title "Marginalia 0.2.0" --notes-file notes.md

## Signing

The app is ad-hoc signed (`codesign --sign -` in `Scripts/bundle.sh`). Recipients of a downloaded copy must right-click → Open once. To remove that prompt you need the paid Apple Developer Program and a Developer ID Application certificate; then sign with it in `bundle.sh`, run `xcrun notarytool submit` on the DMG and `xcrun stapler staple` it. `security find-identity -v -p codesigning` lists the certificates on this machine.

## Versioning

`CFBundleShortVersionString` in `Resources/Info.plist` is the only version source. The CLI reads it (`md --version`), the DMG name uses it, and the tag is `v` plus that value.
