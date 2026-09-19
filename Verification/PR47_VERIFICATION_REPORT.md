# PR 47 verification report

## Snapshot

- PR: `#47` (`feat: evaluate app features on paired Apple devices`)
- Verified source commit: `27d51b087027df6f8b83401362493ba4fbcc76d7`
- Source branch: `codex/developer-dashboard`
- Local verification branch: `codex/pr47-verification`
- Toolchain: Xcode 27.0 (`27A266a`) on macOS 27.2 (`26B5086k`)
- Physical device available: iPhone 16 Pro Max on iOS 27.0; identifiers omitted

The live UI and runtime checks below used the fresh product at
`/private/tmp/PR47UITestDerived/Build/Products/Debug/FoundationEvals.app`.
The older product in `/private/tmp/PR47DesktopDerived` was not used after it was
found to contain a stale September 8 build.
The follow-up disconnect/reconnect check used the rebuilt product at
`/private/tmp/PR47BackendJudgeDerived/Build/Products/Debug/FoundationEvals.app`
and the rebuilt isolated host at `/private/tmp/PR47RunnerHostMacDerived`.

## Outcome

| Area | Result | Evidence |
|---|---|---|
| PR source and CI | Passed | PR remained open and non-draft at the verified commit. All listed GitHub checks passed, including Compile app and tests, Portable regression tests, workflow/script checks, CodeQL, GitGuardian, Socket, and route analysis. |
| Public SDK host builds | Passed | The isolated verification host compiled for macOS and generic iOS with signing disabled. The generated project is ignored and reproducible from `project.yml`. |
| Discovery and explicit pairing | Passed on Mac | The client discovered the verification host, required its displayed code, authenticated, and listed the registered features. No pairing code is retained in this report. |
| Saved-trust reconnect | Passed on Mac | After relaunching both isolated apps with the same stores, the client moved from `Connecting…` to `Connected` without asking for the code again. |
| Same suite on distinct targets | Passed on Mac | The same saved suite ran through the built-in evaluator and through the paired public-SDK host. |
| Real Apple Foundation Model | Passed on Mac | Built-in execution used `On-device · AFM 3 Core Advanced`. A second run invoked `verification.foundation-model` inside the paired host and returned generated text plus framework-reported token usage. This is separate from the deterministic fixture. |
| Initial app-feature judgment | Passed in focused tests | AI-rubric feature runs now require an approved independent judge before feature execution, persist an `.initialRun` assessment, and keep judge failure or cancellation as unscored evidence. Deterministic-only criteria remain local. |
| Deterministic fixture | Passed on Mac | `verification.echo` returned the prompt through the public SDK with saved feature identity and usage. |
| Provenance persistence | Passed | Saved JSON retained runner name, platform, hardware model, OS, app bundle/version, feature ID/version, and protocol version for completed, cancelled, disconnected, and deadline-exceeded runs. |
| Comparison | Passed with expected incompatibility | Compare showed the local run as a selectable baseline and correctly marked the local-model and app-feature runs not comparable because their execution contracts differed. |
| Cancellation | Passed | Cancelling `verification.slow` produced a persisted cancelled run with `developerRunner:cancelled` and a sample error saying the remote run was cancelled. |
| Disconnect | Passed | Terminating only the isolated host during `verification.slow` produced a persisted `developerRunner:disconnected` run with `Runner discovery was lost.` |
| Manual disconnect/reconnect | Passed on Mac | The current client distinguishes an intentional session close from a lost peer, retaining the still-advertised candidate. In the freshly rebuilt two-app flow, Disconnect exposed a usable Connect action and Connect returned to the trusted Connected state immediately without relaunch or re-pairing. |
| Timeout | Passed through fixture | `verification.timeout` produced a persisted `developerRunner:deadlineExceeded` run after about 641 ms. Package tests also verified that expired requests are rejected before application code runs. |
| New suite setup pages | Passed | Scoring, Tools, Structured output, Session profile, and Performance were exercised in the fresh build. Focused UI tests passed for the primary controls and dark rendering. |
| Dark appearance | Passed at wide layout | All five setup pages were inspected from real screenshots and were readable without clipping. |
| Compact layout | Partially passed | A manual compact-width check showed the `Suite setup` pop-up and dark Instructions page without clipping. Every setup page was not re-captured at compact width. |
| Physical iPhone/iPad execution | Blocked / unverified | The iPhone was detected and Developer Mode was available, but installing the host requires Apple Developer provisioning/device-registration mutations. Those were not authorized. No iPad was connected. |

## Runtime evidence

The built-in run completed with a passing AI-rubric assessment, 112 subject
tokens, and a 1.82-second subject request. The paired-host Apple Foundation
Model run returned a distinct generated answer with 71 input and 37 output
tokens. The deterministic fixture returned the original prompt with nine input
tokens.

The originally verified paired-host runs saved `developerExecution` provenance
correctly but left AI-rubric samples unscored. The follow-up implementation now
resolves the suite's approved independent judge before feature execution and
creates a selected `.initialRun` assessment from the immutable saved response.
The focused tests cover a successful verdict, HTTP failure, cancellation, and
missing independent-judge configuration. Failures and cancellation persist as
unscored evidence and never become a pass.

The comparison UI retained both runs and explained the incompatibility rather
than producing a misleading delta. It reported one unchanged case, zero fully
scored comparable cases, and changed subject-model/generation conditions.

## UI findings for follow-up

1. A selected app-feature run shows `Provider not recorded · Local workspace`
   in the status bar even though `developerExecution` provenance is present.
   The footer should identify an app-feature target instead of implying that
   provenance is missing.
2. A disconnected or deadline-exceeded device run presents a generic alert
   whose message is the internal termination key
   (`developerRunner:disconnected` or `developerRunner:deadlineExceeded`). The
   saved run detail has the useful human-readable error, but the alert does not.
3. Resolved in the follow-up: AI-rubric app-feature runs now perform their
   configured independent judge step as part of the initial evaluation.
4. Fixed in the follow-up: clicking Disconnect had cleared authentication before
   the Multipeer `.notConnected` callback, so the callback evicted a peer that
   was still being advertised. Intentional disconnects now retain that candidate
   for the next Connect action. The state-transition regression and the live
   freshly rebuilt two-app Disconnect → Connect flow both pass.

## Visual evidence

- `/private/tmp/foundation-evals-ui-tests/Screenshots/foundation-evals-trace-pr47-dark-scoring.png`
- `/private/tmp/foundation-evals-ui-tests/Screenshots/foundation-evals-trace-pr47-dark-tools.png`
- `/private/tmp/foundation-evals-ui-tests/Screenshots/foundation-evals-trace-pr47-dark-structured-output.png`
- `/private/tmp/foundation-evals-ui-tests/Screenshots/foundation-evals-trace-pr47-dark-session-profile.png`
- `/private/tmp/foundation-evals-ui-tests/Screenshots/foundation-evals-trace-pr47-dark-performance.png`

## Verification commands

- `swift test` — passed: 44 tests in seven portable suites and 14 tests in
  three developer-SDK suites.
- `xcodebuild test -quiet -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -destination 'platform=macOS' -derivedDataPath /private/tmp/PR47BackendJudgeDerived -only-testing:FoundationEvalsTests/EvaluationDevelopmentWorkflowTests CODE_SIGNING_ALLOWED=NO`
  — passed, including initial independent-judge success, fail-closed HTTP error,
  cancellation evidence, and pre-execution configuration rejection.
- `xcodebuild test -quiet -project FoundationEvals.xcodeproj -scheme FoundationEvals -destination 'platform=macOS' -derivedDataPath /private/tmp/PR47UITestDerived -resultBundlePath /private/tmp/PR47UITests-20260919-1930.xcresult -only-testing:FoundationEvalsUITests/FoundationEvalsUITests/testSuiteEditorShowsPrimaryRunControls -only-testing:FoundationEvalsUITests/FoundationEvalsUITests/testSetupPagesRenderInDarkAppearance`
  — passed: 2 tests, 0 failures.
- `xcodebuild build -quiet -project Verification/DeveloperRunnerTestHost/DeveloperRunnerTestHost.xcodeproj -scheme DeveloperRunnerTestHostMac -destination 'platform=macOS' -derivedDataPath /private/tmp/PR47RunnerHostMacDerived CODE_SIGNING_ALLOWED=NO`
  — passed.
- `xcodebuild build -quiet -project Verification/DeveloperRunnerTestHost/DeveloperRunnerTestHost.xcodeproj -scheme DeveloperRunnerTestHost -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/PR47RunnerHostGenericDeviceDerived2 CODE_SIGNING_ALLOWED=NO`
  — passed.
- `plutil -lint` on both generated host plists — passed.

## Remaining device gap

Physical installation is the only acceptance path still blocked. It requires an
explicitly authorized build with automatic provisioning/device registration,
followed by real iPhone pairing, execution, cancellation/disconnect checks, and
saved-run comparison. iPad execution remains unverified until an iPad is
available.


## Presentation corrections after verification

The footer now identifies the persisted app-feature runner instead of showing
`Provider not recorded`. Terminal-run alerts prefer the readable saved sample
error, preserve specific unsaved failure messages, and use readable transport
fallbacks instead of exposing `developerRunner:` keys.

Validation on the integrated dashboard branch:
- `DeveloperRunPresentationTests`: 3 tests passed.
- `WorkspacePresentationTests`: 12 tests passed, including the app-feature footer
  regression and a rendered SwiftUI footer inspected using an explicitly named
  UI fixture. This render is presentation evidence, not a physical-device run.
- Both invocations used `xcodebuild test -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -destination 'platform=macOS' -derivedDataPath /private/tmp/FoundationEvals-PR47-UIFixes CODE_SIGNING_ALLOWED=NO`, selecting the respective suites with `-only-testing`.

The physical provisioning boundary is an actual automatic approval rejection:
registering the connected device and creating/updating Apple Developer signing
profiles requires informed user approval before retrying. The request is pending.
The configured AI-rubric judge path and reconnect finding remain with Sol for
backend correction and verification.
