#!/bin/bash
# Builds ModRunner.app from the SwiftPM executable.
#
#   Scripts/make-app.sh [debug|release]
#
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/ModRunner.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ModRunner"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ModRunner"

# App icon from the brand package.
ICON="$ROOT/brand/macos/ModRunner.icns"
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$APP/Contents/Resources/ModRunner.icns"
else
    echo "warning: $ICON is missing; the app will fall back to the generic icon" >&2
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ModRunner</string>
    <key>CFBundleDisplayName</key><string>ModRunner</string>
    <key>CFBundleIdentifier</key><string>de.incudex.modrunner</string>
    <key>CFBundleExecutable</key><string>ModRunner</string>
    <key>CFBundleIconFile</key><string>ModRunner</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>MED/OctaMED module</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>med</string><string>mmd</string><string>mmd0</string><string>mmd1</string></array>
            <key>LSItemContentTypes</key>
            <array><string>de.incudex.modrunner.med</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>ProTracker module</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>mod</string></array>
            <key>LSItemContentTypes</key>
            <array><string>de.incudex.modrunner.mod</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>de.incudex.modrunner.med</string>
            <key>UTTypeDescription</key><string>MED/OctaMED module</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string><string>public.audio</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>med</string><string>mmd</string><string>mmd0</string><string>mmd1</string></array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>de.incudex.modrunner.mod</string>
            <key>UTTypeDescription</key><string>ProTracker module</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string><string>public.audio</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>mod</string></array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will launch it without a developer certificate.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
