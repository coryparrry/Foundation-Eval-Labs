#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_TAG:?Set RELEASE_TAG}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER}"
: "${GITHUB_SHA:?Set the workflow source commit}"
: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"
: "${RELEASE_BRANCH:?Set the default branch}"
mode="${1:?Pass prepare or publish}"
if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ||
      ! "$GITHUB_SHA" =~ ^[a-f0-9]{40}$ ]]; then
  echo 'Require a vMAJOR.MINOR.PATCH tag, positive build number, and full source SHA.' >&2
  exit 1
fi
if [[ "$mode" != prepare && "$mode" != publish ]]; then
  echo 'Expected prepare or publish.' >&2
  exit 1
fi
if [[ "${GITHUB_REF:-}" != "refs/heads/$RELEASE_BRANCH" || "$(git rev-parse HEAD)" != "$GITHUB_SHA" ]]; then
  echo 'Release only the exact workflow commit dispatched from the default branch.' >&2
  exit 1
fi
if [[ "${PUBLISH_RELEASE:-false}" != false && "${PUBLISH_RELEASE:-false}" != true ]]; then
  echo 'PUBLISH_RELEASE must be true or false.' >&2
  exit 1
fi
if [[ "${PUBLISH_RELEASE:-false}" == true && "${NATIVE_TESTED:-false}" != true ]]; then
  echo 'Publishing requires confirmation of native macOS 27 testing.' >&2
  exit 1
fi

if [[ "$mode" == prepare ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo 'Release requires a clean checkout.' >&2
    exit 1
  fi
  # Read failures abort; never mistake unavailable GitHub metadata for a new tag.
  gh api "repos/$GITHUB_REPOSITORY/releases" --paginate --jq '.[].tag_name' |
    python3 -c 'import os, sys; tags = sys.stdin.read().splitlines(); sys.exit("A release already exists for this tag; use a new version or recover the existing draft manually.") if os.environ["RELEASE_TAG"] in tags else None'
  if git show-ref --verify --quiet "refs/tags/$RELEASE_TAG"; then
    if [[ "$(git rev-parse "$RELEASE_TAG^{commit}")" != "$GITHUB_SHA" ]]; then
      echo 'The existing tag points at different source.' >&2
      exit 1
    fi
  fi
  bash script/verify_release_source.sh "$GITHUB_SHA"
  if ! git show-ref --verify --quiet "refs/tags/$RELEASE_TAG"; then
    # The packaging script requires a tag. Keep it local until packaging succeeds.
    git tag "$RELEASE_TAG" "$GITHUB_SHA"
  fi
else
  filename="Foundation-Evals-${RELEASE_TAG#v}-macOS-arm64.dmg"
  bash script/verify_installer.sh dist/release "$RELEASE_TAG" "$GITHUB_SHA"
  # Draft releases do not create Git refs. Create the tag explicitly so the
  # downloaded installer can be checked against independently resolved source.
  remote_tag="$(gh api "repos/$GITHUB_REPOSITORY/git/matching-refs/tags/$RELEASE_TAG" \
    --jq ".[] | select(.ref == \"refs/tags/$RELEASE_TAG\") | .ref")"
  if [[ -z "$remote_tag" ]]; then
    # A concurrent creator causes this POST to fail; never update or force a ref.
    gh api "repos/$GITHUB_REPOSITORY/git/refs" --method POST \
      -f "ref=refs/tags/$RELEASE_TAG" -f "sha=$GITHUB_SHA" >/dev/null
  fi
  remote_commit="$(gh api "repos/$GITHUB_REPOSITORY/commits/$RELEASE_TAG" --jq .sha)"
  if [[ "$remote_commit" != "$GITHUB_SHA" ]]; then
    echo 'Remote release tag does not resolve to the verified source commit.' >&2
    exit 1
  fi
  gh release create "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" \
    --verify-tag --draft --title "Foundation Evals ${RELEASE_TAG#v}" --generate-notes \
    "dist/release/$filename" dist/release/SHA256SUMS.txt
  # GITHUB_TOKEN publication does not trigger release.yml, so verify inline.
  bash script/verify_release.sh
  if [[ "${PUBLISH_RELEASE:-false}" == true ]]; then
    gh release edit "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --draft=false
  fi
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    release_url="$(gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --json url --jq .url)"
    printf '### Release Me\n\n[%s](%s) at %s. Published: **%s**.\n' \
      "$RELEASE_TAG" "$release_url" "$GITHUB_SHA" "${PUBLISH_RELEASE:-false}" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
