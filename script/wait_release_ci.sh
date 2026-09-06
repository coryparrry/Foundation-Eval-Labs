#!/usr/bin/env bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"
: "${RELEASE_SOURCE_SHA:?Set RELEASE_SOURCE_SHA}"
if [[ ! "$RELEASE_SOURCE_SHA" =~ ^[a-f0-9]{40}$ ]]; then
  echo 'Require a full source SHA.' >&2
  exit 1
fi
# Release Me and CI start on the same push. Wait only for this commit's CI.
for ((attempt=0; attempt<${CI_WAIT_ATTEMPTS:-140}; attempt++)); do
  result="$(gh run list --repo "$GITHUB_REPOSITORY" --workflow ci.yml \
    --commit "$RELEASE_SOURCE_SHA" --branch "${RELEASE_BRANCH:-main}" --event push \
    --limit 1 --json status,conclusion --jq '.[0] | if . == null then "missing" elif .status == "completed" then .conclusion else .status end')"
  case "$result" in
    success) exit 0 ;;
    missing|queued|in_progress|waiting|pending|requested) ;;
    *) echo "Release source CI did not pass: $result" >&2; exit 1 ;;
  esac
  sleep "${CI_WAIT_INTERVAL:-15}"
done
echo 'Timed out waiting for release source CI.' >&2
exit 1
