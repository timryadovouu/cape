#!/bin/bash
# Builds Cape and packages it into Cape.app (accessory app).
set -e
cd "$(dirname "$0")"

# Version: from $VERSION (CI passes the tag), else the latest git tag, else a dev default.
VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null)}"
VERSION="${VERSION#v}"
VERSION="${VERSION:-0.1.0-dev}"
BUILD="${VERSION%%-*}"            # numeric part only, for CFBundleVersion
echo "==> Version $VERSION (build $BUILD)"

echo "==> swift build -c release"
swift build -c release

APP="Cape.app"
BIN="$(swift build -c release --show-bin-path)/Cape"

echo "==> Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cape"

# App icon from Resources/AppIcon.png
if [ -f "Resources/AppIcon.png" ]; then
  echo "==> Building app icon"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
              "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
              "512 512x512" "1024 512x512@2x"; do
    set -- $pair
    sips -z "$1" "$1" "Resources/AppIcon.png" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>Cape</string>
    <key>CFBundleDisplayName</key>      <string>Cape</string>
    <key>CFBundleIdentifier</key>       <string>io.cape.app</string>
    <key>CFBundleVersion</key>          <string>${BUILD}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key>       <string>Cape</string>
    <key>CFBundleIconFile</key>         <string>AppIcon</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>LSMinimumSystemVersion</key>   <string>13.0</string>
    <key>LSUIElement</key>              <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Cape controls Spotify playback from the notch.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Cape records your voice for on-device dictation into the buffer.</string>
</dict>
</plist>
PLIST

# Sign with the stable "Cape Signing" certificate when it's in the keychain (CI
# imports it from secrets). Its designated requirement pins the certificate, not
# this build's hash — so macOS permissions (Accessibility, Microphone) survive
# rebuilds and updates, and the in-app updater can verify a download came from
# the same key. Without it: ad-hoc (permissions reset on every build).
SIGN_ID="${SIGN_ID:-$(security find-identity -p codesigning 2>/dev/null | awk '/"Cape Signing"/ { print $2; exit }')}"
if [ -n "$SIGN_ID" ]; then
  echo "==> Signing with Cape Signing ($SIGN_ID)"
  codesign --force --deep --sign "$SIGN_ID" "$APP"
  codesign --verify --deep --strict "$APP"
elif [ "${REQUIRE_SIGNING:-0}" = "1" ]; then
  echo "error: REQUIRE_SIGNING=1 but no 'Cape Signing' identity is available" >&2
  exit 1
else
  echo "==> No 'Cape Signing' identity — ad-hoc signing (permissions reset on every build)"
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "==> Done: $(pwd)/$APP"
echo "    Run:  open $APP"
