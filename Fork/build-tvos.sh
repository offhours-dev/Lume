#!/usr/bin/env bash
# Fork-only: build the Sideload configuration for a paired Apple TV, signed by the
# free team (Sideload blocks of Lume and LumeTopShelf in the project), and install it with devicectl.
# Usage: Fork/build-tvos.sh [--no-install] [device-id]
# The free-team profile lasts 7 days; re-run to re-sign.
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=1
if [[ "${1:-}" == "--no-install" ]]; then INSTALL=0; shift; fi

DEV=${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/AppleTV/ && /physical/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9A-Fa-f-]{25,}$/) {print $i; exit}}')}
[[ -n "$DEV" ]] || { echo "No paired Apple TV. Pair it in Xcode > Product > Destination > Manage Devices." >&2; exit 1; }

DERIVED=${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/Lume-fork}
LOG=$(mktemp -t lume-tvos-build).log
echo "Building Sideload for device $DEV (log $LOG)"
if ! xcodebuild build \
    -project Lume.xcodeproj -scheme Lume -configuration Sideload \
    -destination "id=$DEV" \
    -clonedSourcePackagesDirPath "$HOME/Library/Developer/Lume-SharedSPM" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration >"$LOG" 2>&1; then
  grep -E 'error:' "$LOG" | sort -u | head -20 >&2
  echo "Build failed; full log: $LOG" >&2
  exit 1
fi

APP="$DERIVED/Build/Products/Sideload-appletvos/Lume.app"
[[ -d "$APP" ]] || { echo "No app at $APP" >&2; exit 1; }
echo "Built: $APP ($(du -sh "$APP" | cut -f1))"
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - | grep -E 'application-identifier|application-groups' -A1 || true
security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw - | sed 's/^/Profile expires: /' || true

if (( INSTALL )); then
  xcrun devicectl device install app --device "$DEV" "$APP"
fi
