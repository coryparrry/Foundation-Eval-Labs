# Releases

Signing and notarization run locally. GitHub-hosted runners execute portable regression tests, compile the macOS 27 app and its test bundles, validate workflows/scripts, and verify uploaded installers. No self-hosted runner or GitHub signing secrets are required.

## Validate a candidate

1. Merge the candidate through a reviewed PR with all required CI checks passing. Wait for the **CI** push run on `main` at the exact candidate commit.
2. On macOS 27 with Xcode 27, run the full native suite using the README instructions. UI tests require an interactive desktop and a signed test runner. Exercise real model generation separately; hosted portable tests do not validate Apple Intelligence or Core AI inference.
3. Tag that exact commit with `vMAJOR.MINOR.PATCH`. Package from its clean checkout. The helper archives committed source into a temporary directory and embeds its SHA in the signed app's `FoundationEvalsSourceCommit` property. Temporary build output avoids Finder metadata interfering with signing.

## Package locally

`script/release.sh` creates the archive, Developer ID signed DMG, Apple notarization ticket, and `SHA256SUMS.txt` under `dist/release`. Supply these environment variables from your local credential store; never commit them or upload them to GitHub:

| Variable | Value |
|---|---|
| `RELEASE_TAG` | `vMAJOR.MINOR.PATCH` matching the candidate tag. |
| `BUILD_NUMBER` | Positive integer for this build. |
| `APPLE_TEAM_ID` | Apple Developer team identifier. |
| `CERTIFICATE_P12_BASE64` | Base64-encoded, password-protected Developer ID certificate/private-key export. |
| `CERTIFICATE_PASSWORD` | Password for that export. |
| `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | Local App Store Connect notarization credentials. |

The helper uses a disposable keychain and restores the original keychain search list on exit. Run `bash script/release.sh` only when you intend to submit the installer to Apple. Packaging does not publish a GitHub release.

## Verify and publish

1. Create a **draft** GitHub release for the validated tag with the DMG and checksum. Tag creation no longer starts a signing job.
2. In Actions, manually dispatch **Release verification** from the protected default branch, supplying the draft's tag. It requires all three current CI jobs to have succeeded on `main` at that tag commit, then downloads the assets and checks the checksum, Developer ID team, signatures, stapled ticket, Gatekeeper assessment, signed source SHA, version, architecture, and Applications shortcut. A legacy compile-only CI run is insufficient.
3. Download and launch the draft installer on macOS 27; confirm its visible workflow. GitHub's macOS 26 runner cannot perform this launch check.
4. Publish only after those checks pass. Publication automatically runs the same read-only verifier again. GitHub does not technically block the Publish button; completing the draft verification is a maintainer release requirement.

The verifier never creates, replaces, or deletes release assets. Published installers from before these CI gates retain their original validation evidence; they cannot satisfy the new source-check gate retrospectively. Keep the repository private until you intend its source and releases to be public. Private downloads require repository access.
