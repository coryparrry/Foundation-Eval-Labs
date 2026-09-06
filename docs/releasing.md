# Releases

## Automatic release PRs

**Release Me** runs on every push to `main`, including PR merges. Release Please collects conventional commits into a version and changelog PR. Merge that release PR to create the version tag and publish the GitHub release with its generated notes. Ordinary merges only create or update the release PR; they do not publish a release. `fix:` changes produce a patch and `feat:` changes produce a minor release. Docs and chores alone do not normally produce a release PR.

The manifest and `version.txt` start at the existing `v1.0.0` release. Tags keep the `vMAJOR.MINOR.PATCH` format. Release Please updates `version.txt`, `CHANGELOG.md`, and `.release-please-manifest.json` in its PR.

Enable **Settings → Actions → General → Workflow permissions → Allow GitHub Actions to create and approve pull requests**. Release Me grants its job permission to write release metadata and PRs. It does not approve or merge PRs. Because PRs created with `GITHUB_TOKEN` do not trigger normal PR workflows, Release Me explicitly dispatches CI on the generated PR branch. You can also manually run Release Me from `main` to retry metadata automation.

GitHub releases initially contain source archives and release notes. Signed DMG installers are attached separately after signing credentials are configured. Automatic release creation does not assert native macOS testing or notarization.

## Attach a signed installer

After the release tag's exact `main` source CI has passed, use **Actions → Package installer → Run workflow** from `main`. Enter the existing release tag and a positive build number higher than the previous installer. The workflow uses the dispatch commit’s protected packaging and verification scripts against a separate checkout of the explicit tag ref, requires its local and remote SHA to match, builds and notarizes the installer, uploads it and its checksum to the existing release, then downloads and verifies both inline.

It never creates or moves tags, creates releases, changes draft/publication status, or overwrites assets. Missing releases, source mismatches, missing CI, and duplicate asset names fail. A partial upload can leave an asset behind; inspect and repair it deliberately before retrying. **Release verification** is manually available for an existing installer; source-only releases do not start installer verification.

Native macOS 27 launch and real model generation remain separate checks. The hosted image runs macOS 26 with Xcode 27, so it compiles the app but cannot launch it. Test the downloaded installer on macOS 27 before describing it as runtime-verified.

## One-time signing setup

In **Settings → Environments → release → Environment secrets**, configure:

| Secret | Value |
|---|---|
| `CERTIFICATE_P12_BASE64` | Base64-encoded, password-protected Developer ID Application certificate and private-key export for team `3Z3955EFRE`. |
| `CERTIFICATE_PASSWORD` | Password for that P12 export. |
| `NOTARY_KEY_P8` | Complete App Store Connect API private key text, including its header and footer. |
| `NOTARY_KEY_ID` | Identifier of that API key. |
| `NOTARY_ISSUER_ID` | Issuer identifier for that API key. |

The existing `release` environment currently needs these five secrets before hosted packaging can run. The workflow reports missing secret names before contacting Apple. Credential values must never appear in source, issue comments, release notes, or command output. Adding local signing keys to GitHub is a separate setup action; adding this workflow does not transfer them.

Restrict the environment to the default branch and configure required reviewers if you want an additional approval before credentials become available. The workflow requires dispatch from the default branch and checks out the selected release tag. Its local and remote tag must resolve to the same source commit. It uses the same hosted `xcode-27` runner as CI. Signing credentials are imported into a disposable keychain, and temporary key material is removed on exit.

## Package locally

Local packaging is also available from a clean checkout of the existing release tag. Set `RELEASE_TAG`, a positive `BUILD_NUMBER`, `APPLE_TEAM_ID`, and the five signing variables listed above, then run `bash script/release.sh`. The script produces the signed, notarized DMG and `SHA256SUMS.txt` in `dist/release`, without publishing anything. Upload both to the existing release without overwriting assets, then run **Release verification** with its tag.

The verifier checks source CI, checksum, Developer ID team, signatures, stapled ticket, Gatekeeper, signed source SHA, version, architecture, and the Applications shortcut. It never creates, replaces, or deletes assets. Private downloads require repository access.
