#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_TAG:?Set RELEASE_TAG to the existing release tag}"
if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Release tags must use vMAJOR.MINOR.PATCH.' >&2
  exit 1
fi
repository="${GITHUB_REPOSITORY:-coryparrry/Foundation-Eval-Labs}"
commit="$(gh api "repos/$repository/commits/$RELEASE_TAG" --jq .sha)"
# Require main CI at the actual tag commit, not an unrelated green run.
run_id="$(gh run list --repo "$repository" --workflow ci.yml --commit "$commit" \
  --branch main --event push --status success --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
if [[ -z "$run_id" ]]; then
  echo "No successful main CI run for release commit $commit." >&2
  exit 1
fi
work="$(mktemp -d "${TMPDIR:-/tmp}/foundation-release-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT
gh run view "$run_id" --repo "$repository" --json jobs > "$work/jobs.json"
python3 script/release_validation.py checks "$work/jobs.json"
filename="Foundation-Evals-${RELEASE_TAG#v}-macOS-arm64.dmg"
gh release download "$RELEASE_TAG" --repo "$repository" --dir "$work" \
  --pattern "$filename" --pattern SHA256SUMS.txt
bash script/verify_installer.sh "$work" "$RELEASE_TAG" "$commit"
echo "Verified $RELEASE_TAG at $commit. Native macOS 27 launch testing remains a separate release check."
