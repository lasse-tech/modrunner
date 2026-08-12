#!/bin/bash
# Packs build/ModRunner.app into a signed, notarised disk image.
#
#   Scripts/make-dmg.sh
#
# The app must already be built and signed with a Developer ID identity —
# `make dmg` does that first. Nothing here needs a tool that macOS does not
# ship: the image is laid out with hdiutil and the Finder, not create-dmg.
#
# Environment:
#   VERSION        marketing version; names the image (default 0.0.0)
#   SIGN_IDENTITY  Developer ID Application identity, for signing the image
#   NOTARY_PROFILE keychain profile from `notarytool store-credentials`.
#                  Empty means: build and sign the image, but do not notarise.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/ModRunner.app"
VERSION="${VERSION:-0.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

VOLUME="ModRunner $VERSION"
DMG="$ROOT/build/ModRunner-$VERSION.dmg"
STAGE="$ROOT/build/dmg-stage"

[[ -d "$APP" ]] || { echo "error: $APP is missing; run make app first" >&2; exit 1; }

# A notarised image has to contain a properly signed app; an ad-hoc signature
# would only be found out minutes later, by the notary service.
if ! codesign --verify --strict "$APP" 2>/dev/null; then
    echo "error: $APP is not validly signed" >&2
    exit 1
fi
if [[ -n "$NOTARY_PROFILE" ]] && \
   ! codesign -dv "$APP" 2>&1 | grep -q "flags=.*runtime"; then
    echo "error: $APP was built without the hardened runtime; notarisation would reject it." >&2
    echo "       Rebuild with SIGN_IDENTITY set." >&2
    exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/ModRunner.app"
ln -s /Applications "$STAGE/Applications"

echo "Building $DMG"
RW="$ROOT/build/ModRunner-rw.dmg"
rm -f "$RW"
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" \
    -fs HFS+ -format UDRW -ov -quiet "$RW"

# Lay the window out: the app on the left, the /Applications drop target on the
# right, at a size that shows both. The Finder needs the volume mounted for
# this, and it is only cosmetic — a failure here must not lose the image.
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -o '/Volumes/.*' | head -1)"
if [[ -n "$MOUNT" ]]; then
    osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "note: could not set the window layout (Finder automation may be denied); the image is still valid" >&2
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 800, 560}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "ModRunner.app" of container window to {150, 190}
        set position of item "Applications" of container window to {450, 190}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
    sync
    hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
fi

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$DMG"
rm -f "$RW"
rm -rf "$STAGE"

if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Built $DMG (not notarised: NOTARY_PROFILE is unset)"
    exit 0
fi

echo "Submitting to the notary service; this usually takes a few minutes."
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# Stapling puts the notarisation ticket inside the image, so Gatekeeper can
# find it on a machine that is offline or behind a filter.
xcrun stapler staple "$DMG"

echo
echo "Gatekeeper's own verdict on the image:"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

echo "Built and notarised $DMG"
