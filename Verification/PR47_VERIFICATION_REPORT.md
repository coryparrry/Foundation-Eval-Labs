# PR 47 verification report

## Snapshot

- PR: `#47` (`feat: evaluate app features on paired Apple devices`)
- Verified source commit: `c4dac19933355429576379aafb07cef6a7d33572`
- Source branch: `codex/developer-dashboard`
- Local verification branch: `codex/pr47-iphone-verification`
- Toolchain: Xcode 27.0 (`27A266a`) on macOS 27.2 (`26B5086k`)
- Physical device available: iPhone 16 Pro Max on iOS 27.0; identifiers omitted

The live UI and runtime checks below used the fresh product at
`/private/tmp/PR47UITestDerived/Build/Products/Debug/FoundationEvals.app`.
The older product in `/private/tmp/PR47DesktopDerived` was not used after it was
found to contain a stale September 8 build.
The follow-up disconnect/reconnect check used the rebuilt product at
`/private/tmp/PR47BackendJudgeDerived/Build/Products/Debug/FoundationEvals.app`
and the rebuilt isolated host at `/private/tmp/PR47RunnerHostMacDerived`.

The physical iPhone host was freshly generated and built while the worktree was
detached at exact `c4dac19`, then signed, installed, and launched from
`/private/tmp/PR47iPhoneC4Derived`. The desktop dashboard used while executing
that physical matrix was the backend-derived product above. Its executable
timestamp predates both `9dd1229` and `c4dac19`, and the bundle does not embed a
Git SHA, so it is treated as a pre-integration dashboard rather than evidence
for the integrated presentation fixes. The stale `/Applications` copy was not
running during the matrix.

After the matrix, a dashboard was freshly built from exact detached `c4dac19`
at `/private/tmp/PR47C4DashboardDerived/Build/Products/Debug/FoundationEvals.app`
and launched against the same isolated workspace. Independent visual inspection
of that product confirmed the saved physical run presentation described below.

## Outcome

| Area | Result | Evidence |
|---|---|---|
| PR source and CI | Passed | PR remained open and non-draft at the verified commit. All listed GitHub checks passed, including Compile app and tests, Portable regression tests, workflow/script checks, CodeQL, GitGuardian, Socket, and route analysis. |
| Public SDK host builds | Passed | The isolated verification host compiled for macOS and generic iOS with signing disabled. The generated project is ignored and reproducible from `project.yml`. |
| Discovery and explicit pairing | Passed on Mac and physical iPhone | The client discovered each verification host, required its displayed code, authenticated, and listed the registered features. No pairing code is retained in this report. |
| Saved-trust reconnect | Passed on Mac and physical iPhone | Relaunching the signed iPhone host restored `Connected` without asking for another code. The runner again advertised the same four features. |
| Same suite on distinct targets | Passed on Mac and physical iPhone | The same saved suite ran through the built-in evaluator, paired Mac host, and paired iPhone host. |
| Real Apple Foundation Model | Passed on physical iPhone | `verification.foundation-model` returned `READY` through `SystemLanguageModel.default`, passed exact scoring in 5.78 seconds, and reported 62 input plus 3 output framework tokens. This is separate from the deterministic fixture. |
| Initial app-feature judgment | Passed in focused tests | AI-rubric feature runs now require an approved independent judge before feature execution, persist an `.initialRun` assessment, and keep judge failure or cancellation as unscored evidence. Deterministic-only criteria remain local. |
| Deterministic fixture | Passed on physical iPhone | Two `verification.echo` runs returned `READY` through the public SDK, passed exact scoring, recorded one input token, and retained the same suite revision and feature identity. |
| Provenance persistence | Passed | Saved JSON retained runner name, platform, hardware model, OS, app bundle/version, feature ID/version, and protocol version for completed, cancelled, disconnected, and deadline-exceeded runs. |
| Comparison | Passed on physical iPhone | Compare selected the first iPhone echo run as the baseline for the second and reported `Comparable`, one unchanged case, and zero regressions. Both runs used the same suite revision, runner, OS, app version, and `verification.echo` feature version. |
| Cancellation | Passed on physical iPhone | Cancelling `verification.slow` produced a persisted cancelled run and a saved sample error saying `The remote run was cancelled.` |
| Disconnect | Passed on physical iPhone | Loss of discovery during `verification.slow` persisted a sample error saying `Runner discovery was lost.` The raw internal alert was observed only in the pre-integration dashboard, not the later c4 presentation check. |
| Manual disconnect/reconnect | Passed on Mac and physical iPhone | The signed iPhone runner reconnected from saved trust after the disconnected run, returned to `Connected`, and exposed all four features without another code. |
| Timeout | Passed on physical iPhone | `verification.timeout` persisted `The verification fixture exceeded its deadline.` after 575 ms. The c4 alert wording is covered by presentation tests but was not freshly exercised end to end on-device. Package tests also verified that expired requests are rejected before application code runs. |
| New suite setup pages | Passed | Scoring, Tools, Structured output, Session profile, and Performance were exercised in the fresh build. Focused UI tests passed for the primary controls and dark rendering. |
| Dark appearance | Passed at wide layout | All five setup pages were inspected from real screenshots and were readable without clipping. |
| Compact layout | Partially passed | A manual compact-width check showed the `Suite setup` pop-up and dark Instructions page without clipping. Every setup page was not re-captured at compact width. |
| Physical iPhone execution | Passed | With explicit authorization, Xcode automatically registered/provisioned the connected iPhone, built and signed the isolated host, installed it, launched it, paired it, and completed success, cancellation, disconnect, reconnect, comparison, and timeout checks. |
| Physical iPad execution | Unverified | No iPad was connected. |

## Runtime evidence

### Physical iPhone

The exact integrated source at `c4dac19` was rebuilt for the connected iPhone
with automatic signing after the user explicitly authorized Apple Developer
device registration and provisioning. The isolated host bundle passed
`codesign --verify --deep --strict`, installed successfully, launched on iOS
27.0, paired explicitly, and advertised four registered features. Device and
pairing identifiers are intentionally omitted.

The physical runs used one deterministic suite (`READY` → `READY`) with Exact
text scoring, so no external judge was contacted:

- Two `verification.echo` runs passed in 119 ms and 206 ms. Both recorded the
  same suite revision, iPhone OS build, app/feature version, and one framework
  input token. Compare marked them `Comparable`, with one unchanged case and no
  regressions.
- `verification.foundation-model` passed in 5.78 seconds and reported 62 input
  and 3 output tokens from the Apple Foundation Models framework.
- Cancelling `verification.slow` persisted `cancelled: true` with `The remote
  run was cancelled.` and retained the iPhone provenance.
- Losing discovery during `verification.slow` persisted `Runner discovery was
  lost.` Relaunching the host reconnected from saved trust without another code.
- `verification.timeout` persisted `The verification fixture exceeded its
  deadline.` in 575 ms.

The saved JSON for all five physical scenarios retained the runner, platform,
OS, app bundle/version, feature ID/version, protocol version, suite revision,
and per-sample outcome. This is persistence evidence, not merely live UI state.

### Dashboard provenance and presentation recheck

The physical matrix executed a c4-built iPhone host through a desktop dashboard
whose executable was produced before the integrated `9dd1229` and `c4dac19`
commits. Its exact source commit cannot be recovered from the bundle. Therefore,
its `Provider not recorded` footer and raw transport-key alerts are not evidence
of defects in the integrated c4 dashboard.

The freshly built c4 dashboard loaded the same saved physical AFM run and
visibly showed `App feature · Foundation Evals verification host · Local
workspace`, correct iPhone and OS provenance, 5.78 seconds, and 65 total tokens.
After relaunching the existing signed host, its Devices sheet showed the physical
iPhone as `Connected` with four registered features. A fresh timeout-alert run
was not completed because the runner option disappeared during selection; this
bounded recheck stopped without reopening the device matrix. Alert wording is
therefore test-covered at c4, but not freshly exercised end to end there.

### Earlier Mac verification

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

The earlier comparison UI retained the local and paired-Mac runs and explained
their incompatibility rather than producing a misleading delta. The later pair
of physical `verification.echo` runs were compatible and produced a valid
unchanged-case comparison.

## UI findings resolution

1. Retracted as an older-dashboard artifact: the `Provider not recorded`
   footer was observed in a pre-integration executable. The freshly built c4
   dashboard correctly identified the saved physical app-feature runner.
2. Retracted as a demonstrated c4 defect: raw `developerRunner:` alert keys were
   observed only in the pre-integration executable. Integrated presentation
   tests cover readable disconnect and deadline-exceeded errors, but the alert
   was not freshly exercised end to end in the bounded c4 device recheck.
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
- `xcodegen generate --spec Verification/DeveloperRunnerTestHost/project.yml`
  — passed; the generated project remains ignored and disposable.
- `xcodebuild build -quiet -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/PR47C4DashboardDerived CODE_SIGNING_ALLOWED=NO`
  — passed from exact detached `c4dac19`; the product was launched against the
  existing isolated verification workspace for the presentation recheck.
- Physical Debug build of `DeveloperRunnerTestHost` with automatic signing,
  provisioning updates, and device registration enabled against the connected
  iPhone — passed from `c4dac19`. The development-team and device identifiers
  are intentionally omitted.
- `codesign --verify --deep --strict` on the physical-device product — passed;
  the signed bundle used Apple Development identity and the expected app bundle.
- `xcrun devicectl device install app` and `device process launch` for the
  isolated host — passed. The installed host then completed the physical run
  matrix described above.
- `plutil -lint` on both generated host plists — passed.

## Remaining device gap

iPhone execution is verified. iPad execution remains unverified until an iPad
is available.


## Presentation-check status after physical verification

The earlier local presentation checks expected the footer to identify the
persisted app-feature runner and terminal alerts to prefer readable errors.
Those tests passed. The later fresh c4 dashboard visual inspection also
confirmed the footer with real saved physical-run evidence, so the footer issue
is closed. The raw alert keys came from the older dashboard; no c4 alert defect
was demonstrated. Because a fresh timeout selection did not complete during the
bounded recheck, readable c4 alert wording remains supported by tests rather
than new physical end-to-end evidence.

Validation on the integrated dashboard branch:
- `DeveloperRunPresentationTests`: 3 tests passed.
- `WorkspacePresentationTests`: 12 tests passed, including the app-feature footer
  regression and a rendered SwiftUI footer inspected using an explicitly named
  UI fixture. This render is presentation evidence, not a physical-device run.
- Both invocations used `xcodebuild test -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -destination 'platform=macOS' -derivedDataPath /private/tmp/FoundationEvals-PR47-UIFixes CODE_SIGNING_ALLOWED=NO`, selecting the respective suites with `-only-testing`.

The physical provisioning boundary was cleared with explicit user approval.
Automatic device registration/provisioning, signed build, installation, launch,
pairing, and the runtime matrix all completed successfully.
The configured AI-rubric judge path and reconnect corrections are now integrated
on the dashboard branch at `9dd1229`. Sol verified initial judging, failure and
cancellation evidence, and a fresh two-app Mac Disconnect → Connect flow without
relaunching or re-pairing, as described above.

The integrated source at `9dd1229` passed 79 focused native tests with zero
failures or skips. Command:
`xcodebuild test -quiet -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -destination 'platform=macOS' -derivedDataPath /private/tmp/FoundationEvals-PR47-UIFixes -only-testing:FoundationEvalsTests/EvaluationDevelopmentWorkflowTests -only-testing:FoundationEvalsTests/DeveloperRunPresentationTests -only-testing:FoundationEvalsTests/WorkspacePresentationTests CODE_SIGNING_ALLOWED=NO`.
This checks the combined backend workflow and UI presentation contracts; it
did not replace the physical-device checks recorded above.
