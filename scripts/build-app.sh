#!/usr/bin/env bash
# Builds MonitorHop with SwiftPM and assembles build/MonitorHop.app.
# Needs only the Xcode Command Line Tools (no Xcode project).
#
# Environment:
#   CONFIG=release|debug        build configuration (default: release)
#   SIGN_IDENTITY=local (default)   stable project-local identity (scripts/dev-signing.sh) so the
#                                   Accessibility permission survives rebuilds
#   SIGN_IDENTITY=-                 ad-hoc signature (permission must be re-granted after each rebuild)
#   SIGN_IDENTITY="Developer ID Application: …"   distribution signing (hardened runtime)
#   VERSION / BUILD_NUMBER      override the version in Info.plist
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MonitorHop"
BUNDLE_ID="com.alencup.MonitorHop"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-local}"
VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="$ROOT/build/$APP_NAME.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# A copy of this bundle that is already running keeps executing the old code: restart it after
# the build so commands forwarded by the CLI reach the new code. Processes are matched by their
# exact executable path (no regex, symlinks resolved); dev mode is preserved.
mkdir -p "$ROOT/build"
EXEC_REAL="$(cd "$ROOT/build" && pwd -P)/$APP_NAME.app/Contents/MacOS/$APP_NAME"
running_pids() {
    local pid
    for pid in $(pgrep -x "$APP_NAME" || true); do
        [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = "$EXEC_REAL" ] && echo "$pid"
    done
    return 0
}
RUNNING_PIDS="$(running_pids)"
RESTART_DEVTOOLS=0
for pid in $RUNNING_PIDS; do
    ps -Eww -o command= -p "$pid" 2>/dev/null | grep -q "MONITORHOP_DEVTOOLS=1" && RESTART_DEVTOOLS=1
done

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "==> generating app icon"
    "$ROOT/scripts/make-icon.sh" || echo "warning: icon generation failed, continuing without icon"
fi
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> codesign (identity: $SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "local" ]; then
    if ! "$ROOT/scripts/dev-signing.sh" sign "$APP"; then
        echo "warning: local signing identity unavailable, falling back to ad-hoc signing"
        codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    fi
elif [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --options runtime --timestamp "$APP"
fi
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => /    requirement: /p'
codesign --verify --strict --verbose=1 "$APP"

if [ -n "$RUNNING_PIDS" ]; then
    echo "==> restarting the running build/ instance"
    # shellcheck disable=SC2086
    kill $RUNNING_PIDS 2>/dev/null || true
    for _ in $(seq 1 30); do [ -z "$(running_pids)" ] && break; sleep 0.1; done
    if [ "$RESTART_DEVTOOLS" = 1 ]; then
        open --env MONITORHOP_DEVTOOLS=1 "$APP"
    else
        open "$APP"
    fi
fi

echo "==> done: $APP ($VERSION build $BUILD_NUMBER)"
