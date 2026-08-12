#!/bin/bash
# Builds ModRunner.app from the SwiftPM executable.
#
#   Scripts/make-app.sh [debug|release]
#
# Environment:
#   VERSION       marketing version for CFBundleShortVersionString (default 0.0.0)
#   BUILD         build number for CFBundleVersion (default: commits on HEAD)
#   SIGN_IDENTITY a codesigning identity; with one set the bundle is signed for
#                 distribution — hardened runtime and a secure timestamp, both
#                 of which notarisation requires. Without one the bundle gets an
#                 ad-hoc signature, which is enough to launch it locally.
#
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/ModRunner.app"
VERSION="${VERSION:-0.0.0}"
BUILD="${BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

cd "$ROOT"
swift build -c "$CONFIG" --product ModRunnerApp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ModRunnerApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ModRunner"

# The interface strings live in the SwiftPM resource bundle that Bundle.module
# resolves. Without it the app traps on the first look-up, so this is not
# optional.
# The strings live in the library target since the split.
BUNDLE="$(swift build -c "$CONFIG" --show-bin-path)/ModRunner_ModRunnerKit.bundle"
if [[ -d "$BUNDLE" ]]; then
    cp -R "$BUNDLE" "$APP/Contents/Resources/"
else
    echo "error: $BUNDLE is missing; the app would have no interface strings" >&2
    exit 1
fi

# Shown by the Licences button in the About panel.
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/" 2>/dev/null || true

# App icon and the two document icons from the brand package. The document
# icons are what the Finder puts on .med and .mod files; rebuild them with
# Scripts/make-doc-icons.swift.
for icon in ModRunner ModRunnerDocMED ModRunnerDocMOD; do
    if [[ -f "$ROOT/brand/macos/$icon.icns" ]]; then
        cp "$ROOT/brand/macos/$icon.icns" "$APP/Contents/Resources/$icon.icns"
    else
        echo "warning: brand/macos/$icon.icns is missing; the Finder will fall back to a generic icon" >&2
    fi
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ModRunner</string>
    <key>CFBundleDisplayName</key><string>ModRunner</string>
    <key>CFBundleIdentifier</key><string>de.incudex.modrunner</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>de</string></array>
    <key>CFBundleExecutable</key><string>ModRunner</string>
    <key>CFBundleIconFile</key><string>ModRunner</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © Lars Gossard. Apache-2.0.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>MED/OctaMED module</string>
            <key>CFBundleTypeIconFile</key><string>ModRunnerDocMED</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>med</string><string>mmd</string><string>mmd0</string><string>mmd1</string></array>
            <key>LSItemContentTypes</key>
            <array><string>de.incudex.modrunner.med</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>ProTracker module</string>
            <key>CFBundleTypeIconFile</key><string>ModRunnerDocMOD</string>
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
            <key>UTTypeIconFile</key><string>ModRunnerDocMED</string>
            <!-- Deliberately not public.audio: nothing else can play a tracker
                 module, and conforming to it hands the type to QuickTime and
                 brings the generic music-note icon with it. -->
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>med</string><string>mmd</string><string>mmd0</string><string>mmd1</string></array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>de.incudex.modrunner.mod</string>
            <key>UTTypeDescription</key><string>ProTracker module</string>
            <key>UTTypeIconFile</key><string>ModRunnerDocMOD</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string></array>
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

if [[ -n "$SIGN_IDENTITY" ]]; then
    # For distribution. The hardened runtime and a timestamp from Apple's
    # server are both preconditions for notarisation; without them the
    # submission comes back rejected rather than failing here.
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    # Ad-hoc signature so macOS will launch it without a developer certificate.
    codesign --force --sign - "$APP" 2>/dev/null || true
fi

echo "Built $APP ($VERSION build $BUILD)"
