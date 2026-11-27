#!/bin/bash
# Build the app and package it with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."
bash build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' AppBundle/Info.plist)
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/nnotch-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto build/nnotch.app "$STAGING/nnotch.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname nnotch -srcfolder "$STAGING" -format UDZO -ov "build/nnotch-${VERSION}-arm64.dmg"
hdiutil verify "build/nnotch-${VERSION}-arm64.dmg"
(cd build && shasum -a 256 "nnotch-${VERSION}-arm64.dmg" > "nnotch-${VERSION}-arm64.dmg.sha256")
