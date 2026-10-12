#!/usr/bin/env bash
# Builds the Swift package, packages it into KeepUp.app (with icon,
# ad-hoc signed), and wraps that into KeepUp.dmg — a normal
# double-click-and-drag-to-Applications installer, like any other Mac app.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="KeepUp"
CONFIG="release"

echo "Building ${APP_NAME} (${CONFIG})…"
swift build -c "$CONFIG"

BIN_PATH=".build/${CONFIG}/${APP_NAME}"
APP_BUNDLE="${APP_NAME}.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "AppResources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "Building app icon…"
ICNS_PATH="AppResources/AppIcon.icns"
iconutil -c icns "AppResources/AppIcon.iconset" -o "$ICNS_PATH"
cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Sign the bundle. Locally (no CODESIGN_IDENTITY set) this ad-hoc signs so
# Gatekeeper doesn't flag a plain unsigned binary, same as always. In CI,
# CODESIGN_IDENTITY is set to a real "Developer ID Application: ..." identity
# and hardened runtime is turned on, which is required for notarization.
# Must run last: the signature needs to cover everything already in the
# bundle.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$CODESIGN_IDENTITY" = "-" ]; then
  codesign --force --deep -s - "$APP_BUNDLE" >/dev/null 2>&1 || true
else
  echo "Signing with Developer ID identity: ${CODESIGN_IDENTITY}…"
  codesign --force --options runtime --timestamp -s "$CODESIGN_IDENTITY" "$APP_BUNDLE"
fi

echo "Built ${APP_BUNDLE}."
echo "Building installer disk image…"

DMG_NAME="${APP_NAME}.dmg"
STAGING_DIR=".dmg_staging"

rm -rf "$STAGING_DIR" "$DMG_NAME"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME" >/dev/null

rm -rf "$STAGING_DIR"

if [ "$CODESIGN_IDENTITY" = "-" ]; then
cat <<EOF

Done! Open ${DMG_NAME} and drag KeepUp into the Applications
shortcut — the same way you'd install any app from a downloaded DMG.

First-launch note: since this isn't signed by a paid Apple Developer
account, macOS will say it's "from an unidentified developer" the very
first time you open it from /Applications. Right-click (Control-click)
KeepUp there and choose Open, then click Open again in the dialog
that appears. That's a one-time step — after that, double-clicking it
normally (Launchpad, Spotlight, Dock) always just works.
EOF
else
cat <<EOF

Done! Built ${DMG_NAME}, signed with a Developer ID identity.
If this ran in CI with notarization credentials configured, the
workflow notarizes and staples the ticket to this DMG next — the
result opens normally on any Mac with no Gatekeeper warning at all.
EOF
fi
