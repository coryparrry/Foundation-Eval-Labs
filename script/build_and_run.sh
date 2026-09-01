#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
CONFIGURATION="Debug"
PCC_MODE=false
XCODE_SIGNING_ARGUMENTS=()
if [[ "$MODE" == "--pcc" || "$MODE" == "pcc" ]]; then
  PCC_MODE=true
  CONFIGURATION="Release"
  MODE="run"
  PCC_TEAM_ID="${FOUNDATION_EVALS_TEAM_ID:-}"
  PCC_SIGNING_IDENTITY="${FOUNDATION_EVALS_SIGNING_IDENTITY:-Apple Development}"
  if [[ ! "$PCC_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Set FOUNDATION_EVALS_TEAM_ID to the 10-character Apple Developer team approved for Private Cloud Compute." >&2
    exit 4
  fi
  if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -F "$PCC_SIGNING_IDENTITY" >/dev/null; then
    echo "No installed code-signing identity matches '$PCC_SIGNING_IDENTITY'." >&2
    exit 4
  fi
  XCODE_SIGNING_ARGUMENTS=(
    "DEVELOPMENT_TEAM=$PCC_TEAM_ID"
    "CODE_SIGN_IDENTITY=$PCC_SIGNING_IDENTITY"
  )
  echo "Building the entitled Release configuration for team $PCC_TEAM_ID with $PCC_SIGNING_IDENTITY."
fi
APP_NAME="FoundationEvals"
BUNDLE_ID="com.coryparry.FoundationEvals"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/FoundationEvals/FoundationEvals.xcodeproj"
BUILD_ROOT="$(mktemp -d /tmp/FoundationEvals-build.XXXXXX)"
trap 'rm -rf -- "$BUILD_ROOT"' EXIT
DERIVED_DATA="$BUILD_ROOT/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BUNDLE="$ROOT_DIR/dist/Foundation Evals.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if pgrep -x "$APP_NAME" >/dev/null; then
  echo "Foundation Evals is already running. Finish or cancel its run, then quit it before rebuilding." >&2
  exit 3
fi

XCODEBUILD_ARGUMENTS=(
  -project "$PROJECT"
  -scheme "$APP_NAME"
  -configuration "$CONFIGURATION"
  -destination "platform=macOS"
  -derivedDataPath "$DERIVED_DATA"
)
if [[ "$PCC_MODE" == true ]]; then
  XCODEBUILD_ARGUMENTS+=(-allowProvisioningUpdates)
  XCODEBUILD_ARGUMENTS+=("${XCODE_SIGNING_ARGUMENTS[@]}")
fi
xcodebuild "${XCODEBUILD_ARGUMENTS[@]}" build
/usr/bin/codesign --verify --strict --deep "$BUILT_APP"

if [[ "$PCC_MODE" == true ]]; then
  BUILT_TEAM_ID="$(/usr/bin/codesign -dv --verbose=4 "$BUILT_APP" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
  if [[ -z "$BUILT_TEAM_ID" || "$BUILT_TEAM_ID" != "$PCC_TEAM_ID" ]]; then
    echo "The Release app is not signed by the requested Apple Developer team." >&2
    exit 5
  fi
  if ! /usr/bin/codesign -d --entitlements :- "$BUILT_APP" 2>/dev/null \
      | /usr/bin/plutil -extract com.apple.developer.private-cloud-compute raw - \
      | /usr/bin/grep -qx true; then
    echo "The signed Release app does not contain the approved Private Cloud Compute entitlement." >&2
    exit 5
  fi
fi

mkdir -p "$ROOT_DIR/dist"
rm -rf -- "$APP_BUNDLE"
ditto "$BUILT_APP" "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--pcc|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
