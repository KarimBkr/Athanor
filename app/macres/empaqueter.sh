#!/usr/bin/env bash
# Builds the macOS app bundle: empaqueter.sh DEST/Athanor.app BINARY [BINARY...]
# Several binaries (arm64 and amd64) are joined into one universal program (lipo, or llvm-lipo off a Mac).
# The bundle goes at the root of the tool folder: the app finds commands/, system/ and template/ next to
# it, and keeps its settings there (app/config.go, dossierExe). The version comes from winres/athanor.rc.
# On a Mac the bundle gets an ad hoc signature (Apple chips refuse unsigned programs); built elsewhere,
# the Go linker signs the binaries ad hoc itself.
set -eu
ici="$(cd "$(dirname "$0")" && pwd)"
app="$1"; shift
[ $# -ge 1 ] || { echo "usage: empaqueter.sh DEST/Athanor.app BINARY [BINARY...]" >&2; exit 2; }
version=$(sed -n 's/.*VALUE "ProductVersion", *"\([0-9.]*\)".*/\1/p' "$ici/../winres/athanor.rc" | head -n 1)
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [ $# -gt 1 ]; then
  lipo=$(command -v lipo || command -v llvm-lipo || ls /usr/bin/llvm-lipo* 2>/dev/null | head -n 1)
  [ -n "$lipo" ] || { echo "lipo (or llvm-lipo) is missing: cannot join the binaries" >&2; exit 1; }
  "$lipo" -create "$@" -output "$app/Contents/MacOS/athanor"
else
  cp "$1" "$app/Contents/MacOS/athanor"
fi
chmod 755 "$app/Contents/MacOS/athanor"
# the bundle's program is a launcher: it starts the application detached and ends at once, so that every
# double click runs it again (an application already running then opens a window: main.go, --lancer)
printf '#!/bin/sh\nexec "$(dirname "$0")/athanor" --lancer "$@"\n' > "$app/Contents/MacOS/lanceur"
chmod 755 "$app/Contents/MacOS/lanceur"
cp "$ici/athanor.icns" "$app/Contents/Resources/athanor.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Athanor</string>
	<key>CFBundleDisplayName</key><string>Athanor</string>
	<key>CFBundleIdentifier</key><string>com.athanor.app</string>
	<key>CFBundleExecutable</key><string>lanceur</string>
	<key>CFBundleIconFile</key><string>athanor</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${version:-0}</string>
	<key>CFBundleVersion</key><string>${version:-0}</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
if command -v codesign >/dev/null 2>&1; then codesign -s - -f --deep "$app" >/dev/null 2>&1 || true; fi
echo "$app ready (version ${version:-?})"
