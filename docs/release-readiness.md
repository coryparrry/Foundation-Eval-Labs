# Release readiness

This repository contains development source. A local build is not evidence of a signed, notarized distribution, and no release is certified by this checklist.

## Source distribution

- The project uses the MIT license in `LICENSE`.
- [Third-party notices](../FoundationEvals/FoundationEvals/Resources/THIRD_PARTY_NOTICES.txt) reproduce 49 tracked license/notice files from the 31 package revisions in `Package.resolved`, including nested and test-only material. Regenerate them when dependencies change; they do not cover separately supplied model resources.
- README documents development tests, providers, local storage, and the unauthenticated loopback MCP boundary.
- The worklog is historical. Review current code and fresh validation results when deciding whether to release.

## Remaining app distribution work

- Supply a macOS app icon. The current AppIcon catalog has empty slots.
- Create and verify the intended Developer ID distribution artifact, then complete notarization and stapling. None of these release steps is claimed as completed here. Hardened runtime is enabled in the project; that setting alone does not verify the artifact.
- Exercise the packaged app's model readiness, evaluation, save/reopen/export, custom provider, and MCP workflows. Core AI inference also needs compatible external resources.

No GitHub publication, notarization submission, or release upload is part of this source cleanup.

## Cleanup review — 2026-09-05

- Deleted 96 untracked, byte-identical numbered copies after comparing each with its retained original: 84 Swift files, nine Markdown files, two Python files, and one text file. A subsequent content-hash scan found no remaining identical files across application source, docs, examples, and scripts (excluding generated user/build state).
- Removed two uncalled helpers (`MCPRPCRequest.objectParameter` and `CoreAIModelLoader.clear`) and 36 iOS/visionOS build settings from the macOS-only project. Framework and protocol callbacks were retained.
- Fixed completed-run save recovery, including restart while storage is unavailable; interrupted runs now preserve their provider configuration. Added failure/restart regression coverage.
- Fixed delegate-backed custom-tool HTTP sessions surviving the client lifetime. Added a session-release regression check.
- Reviewed MCP and custom-provider boundaries and independently reviewed the persistence fixes. No further confirmed finding remained in those scoped reviews; this is not a guarantee that all code is bug-free.
- Scanned 679 reachable Git objects across 31 commits for recognizable private-key, GitHub, OpenAI, and AWS credential patterns, with no matches. No personal home paths were found in tracked files. These bounded checks cannot detect every possible secret.
- Kept the existing staged CodeGraph ignore file separate from the cleanup. No Git remote was configured and no GitHub operation was performed.

## Local validation

The Release configuration builds successfully with `xcodebuild -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/foundation-evals-release-review build`. `codesign --verify --strict --deep` passes for the resulting app, and its bundled `THIRD_PARTY_NOTICES.txt` matches the source file byte-for-byte and contains the project MIT license. The artifact is ad-hoc signed with hardened runtime and no TeamIdentifier; this checks local integrity, not Developer ID distribution or notarization.

An attempted Release test run could not import the app with `@testable` because the production configuration disables testability. Tests are therefore run under Debug; production settings were retained.

Final test coverage: **239 unit tests passed, one Core AI resource-dependent test skipped, and both UI tests passed in their latest relevant runs**. The full Debug run validated the unit suite and case-selection UI. The primary-controls UI test initially failed because its disclosure click missed the visible chevron; after correcting the measured click inset, its targeted rerun passed. No product UI behavior was changed to accommodate the test.

Commands used for Debug verification (with isolated Derived Data and result bundles under `/tmp`):

```sh
xcodebuild -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/foundation-evals-release-review -resultBundlePath /tmp/foundation-evals-final-debug-tests.xcresult test
xcodebuild -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/foundation-evals-release-review -resultBundlePath /tmp/foundation-evals-final-ui-tests.xcresult -only-testing:FoundationEvalsUITests test
xcodebuild -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/foundation-evals-release-review -resultBundlePath /tmp/foundation-evals-disclosure-final.xcresult -only-testing:FoundationEvalsUITests/FoundationEvalsUITests/testSuiteEditorShowsPrimaryRunControls test
```

The first two commands had the pre-fix disclosure failure; the final targeted command succeeded. `plutil -lint FoundationEvals/FoundationEvals.xcodeproj/project.pbxproj`, `bash -n script/build_and_run.sh`, and `git diff --check` also passed.
