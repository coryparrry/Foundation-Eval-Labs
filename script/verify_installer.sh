#!/usr/bin/env bash
set -euo pipefail
: "${EXPECTED_TEAM_ID:?Set the expected Developer ID team}"
directory="${1:?Pass the installer directory}"
tag="${2:?Pass its vMAJOR.MINOR.PATCH tag}"
expected_commit="${3:-}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || ! "$EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo 'Invalid release tag or Developer ID team.' >&2
  exit 1
fi
if [[ -n "$expected_commit" && ! "$expected_commit" =~ ^[a-f0-9]{40}$ ]]; then
  echo 'Expected source commit must be a full Git SHA.' >&2
  exit 1
fi
version="${tag#v}"
filename="Foundation-Evals-$version-macOS-arm64.dmg"
python3 "$(dirname "$0")/release_validation.py" checksum "$directory" "$filename"
dmg="$directory/$filename"
requirement="anchor apple generic and certificate leaf[subject.OU] = \"$EXPECTED_TEAM_ID\""
codesign --verify --strict -R "=$requirement" "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
mountpoint="$(mktemp -d "${TMPDIR:-/tmp}/foundation-installer-check.XXXXXX")"
mounted=false
cleanup() {
  result=$?
  if [[ "$mounted" == true ]]; then
    # Gatekeeper can briefly retain the mount while its assessment finishes.
    for attempt in 1 2 3; do
      if hdiutil detach "$mountpoint" >/dev/null; then
        mounted=false
        break
      fi
      sleep "$attempt"
    done
    if [[ "$mounted" == true ]]; then
      echo "Could not detach verification mount: $mountpoint" >&2
      result=1
    fi
  fi
  rmdir "$mountpoint" 2>/dev/null || true
  exit "$result"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mountpoint" "$dmg"
mounted=true
app="$mountpoint/Foundation Evals.app"
codesign --verify --strict --deep -R "=$requirement" "$app"
spctl --assess --type execute --verbose=2 "$app"
test "$(readlink "$mountpoint/Applications")" = /Applications
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$version"
if [[ -n "$expected_commit" ]]; then
  test "$(/usr/libexec/PlistBuddy -c 'Print :FoundationEvalsSourceCommit' "$app/Contents/Info.plist")" = "$expected_commit"
fi
test "$(lipo -archs "$app/Contents/MacOS/FoundationEvals")" = arm64
