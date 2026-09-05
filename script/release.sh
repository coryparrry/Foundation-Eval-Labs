#!/usr/bin/env bash
set -euo pipefail

# CI only: credentials are imported into a disposable runner keychain.
: "${RUNNER_TEMP:?Run from the Release workflow}"
: "${RELEASE_TAG:?Missing release tag}"
: "${APPLE_TEAM_ID:?Configure APPLE_TEAM_ID in the release environment}"
: "${CERTIFICATE_P12_BASE64:?Configure the release environment signing secrets}"
: "${CERTIFICATE_PASSWORD:?Missing CERTIFICATE_PASSWORD}"
: "${NOTARY_KEY_P8:?Missing NOTARY_KEY_P8}"
: "${NOTARY_KEY_ID:?Missing NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?Missing NOTARY_ISSUER_ID}"
if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Release tags must have the form v1.0.0.' >&2
  exit 1
fi

cd "$(dirname "$0")/.."
version="${RELEASE_TAG#v}"
work="$(mktemp -d "$RUNNER_TEMP/foundation-evals-release.XXXXXX")"
keychain="$work/signing.keychain-db"
keychain_password="$(openssl rand -hex 24)"
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then hdiutil detach "$work/mount" >/dev/null || true; fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
umask 077
printf '%s' "$CERTIFICATE_P12_BASE64" | base64 --decode > "$work/signing.p12"
printf '%s' "$NOTARY_KEY_P8" > "$work/notary.p8"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/signing.p12" -P "$CERTIFICATE_PASSWORD" -t cert -f pkcs12 \
  -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
identity="$(security find-identity -v -p codesigning "$keychain" |
  awk -v team="($APPLE_TEAM_ID)" '/Developer ID Application:/ && index($0, team) {print $2}')"
if [[ ! "$identity" =~ ^[A-Fa-f0-9]{40}$ ]]; then
  echo 'The P12 must contain exactly one valid Developer ID Application identity for APPLE_TEAM_ID.' >&2
  exit 1
fi

xcodebuild -version
xcodebuild archive \
  -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$work/build" -archivePath "$work/FoundationEvals.xcarchive" \
  ARCHS=arm64 CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" OTHER_CODE_SIGN_FLAGS=--timestamp \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}"

export APPLE_TEAM_ID
python3 - "$work/ExportOptions.plist" "$identity" <<'PY'
import os, plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({'method': 'developer-id', 'signingStyle': 'manual',
                  'teamID': os.environ['APPLE_TEAM_ID'],
                  'signingCertificate': sys.argv[2]}, output)
PY
xcodebuild -exportArchive -archivePath "$work/FoundationEvals.xcarchive" \
  -exportPath "$work/export" -exportOptionsPlist "$work/ExportOptions.plist"
mkdir -p "$work/payload"
app="$work/payload/Foundation Evals.app"
ditto --norsrc --noextattr "$work/export/FoundationEvals.app" "$app"
xattr -cr "$app"
codesign --verify --strict --deep "$app"
test -f "$app/Contents/Resources/AppIcon.icns"
ln -s /Applications "$work/payload/Applications"
dmg="$work/Foundation-Evals-$version-macOS-arm64.dmg"
hdiutil create -volname 'Foundation Evals' -srcfolder "$work/payload" -format UDZO "$dmg"
codesign --sign "$identity" --timestamp "$dmg"

notary_auth=(--key "$work/notary.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
xcrun notarytool submit "$dmg" "${notary_auth[@]}" --wait --timeout 30m \
  --output-format json > "$work/notarization.json"
python3 - "$work/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print('Apple notarization:', result.get('status'), result.get('id'))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; inspect the submission in Apple Notary.')
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
mkdir "$work/mount"
hdiutil attach -readonly -nobrowse -mountpoint "$work/mount" "$dmg"
mounted=true
codesign --verify --strict --deep "$work/mount/Foundation Evals.app"
spctl --assess --type execute --verbose=2 "$work/mount/Foundation Evals.app"
test "$(readlink "$work/mount/Applications")" = /Applications
hdiutil detach "$work/mount"
mounted=false
mkdir -p dist/release
cp "$dmg" dist/release/
(cd dist/release && shasum -a 256 "$(basename "$dmg")" > SHA256SUMS.txt)
