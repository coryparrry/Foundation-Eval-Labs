# Releases

The [private GitHub repository](https://github.com/coryparrry/Foundation-Eval-Labs) runs two workflows:

- **CI** checks script/example syntax and compiles the app and both test bundles on pull requests and pushes. GitHub's `xcode-27` runner currently runs macOS 26, so it cannot execute this macOS 27 app's tests. Run the tests locally using the README command before tagging a release.
- **Release** builds a Developer ID archive, exports the app, creates a drag-to-Applications DMG, submits it to Apple, staples the accepted ticket, verifies the signatures and Gatekeeper assessment, and creates a **draft** GitHub Release with the DMG and SHA-256 checksum.

## One-time signing setup

In **Settings → Environments → release**, configure the following. Never commit signing keys or paste them into an issue or build log.

| Setting | Type | Value |
|---|---|---|
| `APPLE_TEAM_ID` | Variable | Your Apple Developer team ID. |
| `CERTIFICATE_P12_BASE64` | Secret | Base64-encoded export of the **Developer ID Application** certificate and its private key, as a password-protected `.p12`. |
| `CERTIFICATE_PASSWORD` | Secret | Password protecting that `.p12`. |
| `NOTARY_KEY_P8` | Secret | Contents of the App Store Connect team API key `.p8` file. |
| `NOTARY_KEY_ID` | Secret | ID of that API key. |
| `NOTARY_ISSUER_ID` | Secret | Issuer ID for the team API key. |

The Developer ID identity must belong to `APPLE_TEAM_ID`. Use a team API key with permission to submit notarizations. The runner imports credentials into a temporary keychain and removes its keychain and working files on exit. Secrets are only supplied to the release job; pull-request CI does not use them.

See [GitHub's Apple signing setup](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications) and [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Create a release

1. Confirm CI passed for the commit and run the macOS 27 tests locally.
2. Create and push a version tag on that commit:

   ```sh
   git tag -a v1.0.0 -m "Foundation Evals 1.0.0"
   git push origin v1.0.0
   ```

3. Wait for the **Release** workflow to finish. It uses the tag's version for the app and the workflow run number for the build number.
4. Open the draft under **Releases**, review the notes, download and try the DMG, then choose **Publish release**.

Tags must use `vMAJOR.MINOR.PATCH`. The workflow can also be dispatched against an existing tag. It fails if a release with that tag already exists, so it never silently replaces published assets. Keep the repository private until you intend its source and releases to be public; private release downloads require repository access.
