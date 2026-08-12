#!/bin/bash
# Publishes a notarised disk image as a GitHub release.
#
#   VERSION=1.0.0 Scripts/make-release.sh
#
# Expects build/ModRunner-$VERSION.dmg to exist and to be notarised — `make
# release` builds it first. The release notes are the section for this version
# out of CHANGELOG.md.
#
# Environment:
#   VERSION  the version to publish; the tag is v$VERSION
#   DRAFT    1 to create the release as a draft (default 1, so nothing goes
#            public until you have looked at it)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-}"
DRAFT="${DRAFT:-1}"
TAG="v$VERSION"
DMG="$ROOT/build/ModRunner-$VERSION.dmg"

[[ -n "$VERSION" ]] || { echo "error: VERSION is not set (make release VERSION=1.0.0)" >&2; exit 1; }
[[ -f "$DMG" ]] || { echo "error: $DMG is missing; run make dmg first" >&2; exit 1; }
command -v gh >/dev/null || { echo "error: the gh command line is not installed" >&2; exit 1; }

# An unstapled image would greet everyone who downloads it with a Gatekeeper
# warning, and there is no taking a release asset back once it is out.
if ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    echo "error: $DMG carries no notarisation ticket. Publishing it would put" >&2
    echo "       a Gatekeeper warning in front of every download." >&2
    exit 1
fi

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "error: the working tree is dirty; commit before tagging a release" >&2
    exit 1
fi

# The changelog section for this version: from its heading to the next one.
NOTES="$(awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
' "$ROOT/CHANGELOG.md")"

if [[ -z "$(echo "$NOTES" | tr -d '[:space:]')" ]]; then
    echo "error: CHANGELOG.md has no '## [$VERSION]' section" >&2
    exit 1
fi

if ! git -C "$ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    git -C "$ROOT" tag -a "$TAG" -m "ModRunner $VERSION"
fi
git -C "$ROOT" push origin "$TAG"

ARGS=(--title "ModRunner $VERSION" --notes "$NOTES")
if [[ "$DRAFT" == "1" ]]; then
    ARGS+=(--draft)
    STATE=" (draft — publish it from the release page when you are happy)"
else
    STATE=""
fi

gh release create "$TAG" "$DMG" "${ARGS[@]}"
echo "Created release $TAG$STATE"
