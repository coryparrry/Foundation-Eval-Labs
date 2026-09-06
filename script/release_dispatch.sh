#!/usr/bin/env bash
set -euo pipefail
script_directory="$(cd "$(dirname "$0")" && pwd)"
cd "${SOURCE_DIR:-$script_directory/..}"
: "${RELEASE_TAG:?Set RELEASE_TAG}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER}"
: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"
: "${RELEASE_BRANCH:?Set the default branch}"
mode="${1:?Pass prepare or publish}"
if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo 'Require a vMAJOR.MINOR.PATCH tag and positive build number.' >&2
  exit 1
fi
if [[ "$mode" != prepare && "$mode" != publish ]]; then
  echo 'Expected prepare or publish.' >&2
  exit 1
fi
if [[ "${GITHUB_REF:-}" != "refs/heads/$RELEASE_BRANCH" ]]; then
  echo 'Dispatch installer packaging from the default branch.' >&2
  exit 1
fi
source_commit="$(git rev-parse HEAD)"
remote_commit="$(gh api "repos/$GITHUB_REPOSITORY/commits/$RELEASE_TAG" --jq .sha)"
if [[ "$remote_commit" != "$source_commit" || "$(git rev-parse "$RELEASE_TAG^{commit}")" != "$source_commit" ]]; then
  echo 'Release tag must resolve to the exact checked-out source.' >&2
  exit 1
fi
# Require the release created by Release Please; never create or move a tag.
gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --json url >/dev/null
if [[ "$mode" == prepare ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo 'Installer packaging requires a clean checkout.' >&2
    exit 1
  fi
  bash "$script_directory/verify_release_source.sh" "$source_commit"
else
  filename="Foundation-Evals-${RELEASE_TAG#v}-macOS-arm64.dmg"
  bash "$script_directory/verify_installer.sh" dist/release "$RELEASE_TAG" "$source_commit"
  # No --clobber: existing assets must never be silently replaced.
  gh release upload "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" \
    "dist/release/$filename" dist/release/SHA256SUMS.txt
  # Asset uploads with GITHUB_TOKEN do not trigger a verification workflow.
  bash "$script_directory/verify_release.sh"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    release_url="$(gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --json url --jq .url)"
    printf '### Installer attached\n\n[%s](%s) at %s. Native macOS 27 testing remains separate.\n' \
      "$RELEASE_TAG" "$release_url" "$source_commit" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
