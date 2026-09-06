# Releases

Use **Actions → Release Me → Run workflow** to build, sign, notarize, and prepare a GitHub release. It runs only when manually dispatched from the default branch. A successful run creates a **draft** by default; publication is an explicit choice. The workflow works with private and public repositories and does not change repository visibility.

## One-time signing setup

In **Settings → Environments → release → Environment secrets**, configure:

| Secret | Value |
|---|---|
| `CERTIFICATE_P12_BASE64` | Base64-encoded, password-protected Developer ID Application certificate and private-key export for team `3Z3955EFRE`. |
| `CERTIFICATE_PASSWORD` | Password for that P12 export. |
| `NOTARY_KEY_P8` | Complete App Store Connect API private key text, including its header and footer. |
| `NOTARY_KEY_ID` | Identifier of that API key. |
| `NOTARY_ISSUER_ID` | Issuer identifier for that API key. |

The existing `release` environment currently needs these five secrets before hosted packaging can run. The workflow reports missing secret names before creating a tag or contacting Apple. Credential values must never appear in source, issue comments, release notes, or command output. Adding local signing keys to GitHub is a separate setup action; adding this workflow does not transfer them.

Restrict the environment to the default branch and configure required reviewers if you want an additional approval before credentials become available. The workflow also checks the dispatch branch and packages the immutable commit captured when the run started. It uses the same hosted `xcode-27` runner as CI. Signing credentials are imported into a disposable keychain, and temporary key material is removed on exit.

## Run Release Me

1. Merge the candidate through a reviewed PR and wait for the **CI** push run on `main` at that exact commit. Release Me requires all three checks: **Compile app and tests**, **Portable regression tests**, and **Workflow and script checks**.
2. On macOS 27 with Xcode 27, run the full native suite using the README instructions. UI tests require an interactive desktop and a signed test runner. Exercise real model generation separately; hosted CI does not validate Apple Intelligence or Core AI inference.
3. Open **Actions → Release Me → Run workflow**, select the default branch, enter a new `vMAJOR.MINOR.PATCH` tag and a positive build number higher than the previous release. Leave **Publish after verification** unchecked to create a draft for inspection. To publish in the same run, explicitly select it and confirm native macOS 27 testing.
4. The workflow checks source CI, creates a local tag, archives committed source, embeds its SHA in the signed app, signs and notarizes the DMG, and verifies the installer. Only after packaging succeeds does it create the remote Git tag at the verified source SHA, confirm that tag resolves correctly, create the GitHub draft, upload the DMG and checksum, then download and verify them again. An existing tag is accepted only if it resolves to the same commit; tags are never moved. If publication was selected, the verified draft is published.
5. Download and launch the installer on macOS 27 before publishing a draft. Its release link is in the workflow summary. You retain GitHub's normal **Publish release** control after inspection.

No release runs on a push, merge, or tag creation. Existing releases are never overwritten. A failed build leaves no remote tag or draft. A later failure can leave a remote tag without a draft; retrying Release Me is allowed only from the same source commit, and the existing tag must still match. A failure after draft creation can leave a draft for inspection. For that case, repair the draft manually, run **Release verification** with its tag, and publish only when the checks pass. Remote lookup errors, tag creation races, and source mismatches abort without moving or deleting any tag. Do not retry Release Me against an existing release.

The hosted image runs macOS 26 with Xcode 27, so it can compile the macOS 27 app but cannot launch it. The native-testing confirmation records the maintainer's assertion; it is not automated native proof. GitHub does not technically block its normal Publish button. Release Me verifies downloads inline because releases published with `GITHUB_TOKEN` do not trigger another workflow; manual publication runs the existing read-only verifier.

## Package locally

Local packaging remains available with the same verification and credential handling. Tag the validated commit, use a clean checkout of that tag, and run `bash script/release.sh` with these environment variables from your local credential store:

| Variable | Value |
|---|---|
| `RELEASE_TAG` | `vMAJOR.MINOR.PATCH` matching the candidate tag. |
| `BUILD_NUMBER` | Positive integer for this build. |
| `APPLE_TEAM_ID` | Apple Developer team identifier (`3Z3955EFRE` for this app). |
| `CERTIFICATE_P12_BASE64`, `CERTIFICATE_PASSWORD` | Local Developer ID certificate/private-key export and its password. |
| `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | Local App Store Connect notarization credentials. |

The helper writes the signed, notarized DMG and `SHA256SUMS.txt` to `dist/release`. It archives into a temporary directory to avoid Finder metadata interfering with signing and restores the original keychain search list on exit. Run it only when you intend to submit the installer to Apple. Local packaging does not publish a GitHub release.

Create a draft with both files and dispatch **Release verification** with its tag before publishing. The verifier checks source CI, checksum, Developer ID team, signatures, stapled ticket, Gatekeeper, signed source SHA, version, architecture, and Applications shortcut. It never creates, replaces, or deletes assets. Older installers retain their original evidence; legacy compile-only CI cannot satisfy the current source gate retrospectively. Private downloads require repository access.
