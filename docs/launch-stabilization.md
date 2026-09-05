# Launch stabilization

Feature scope was frozen on 5 September 2026. The release goal is a dependable native evaluation workflow: edit a suite, run it, understand the score or error, inspect/export the result, and reopen saved history. Complete Apple API coverage is no longer a launch requirement.

## Exit checks

- Cancellation is recorded as cancellation, and systemic provider failures stop the batch before later samples. The transcript error option controls preserved history, not whether the batch continues.
- MCP suite reads and replacements preserve field assertions, including older clients that omit the optional field; an explicit empty array clears them.
- The refusal timeout and Spotlight recording-drain regressions pass, followed by the integrated code test suite.
- Normal model controls remain easy to reach; advanced settings remain available and retain their values.
- The installed build completes positive and negative scoring examples, supports inspecting/exporting results, and retains them after relaunch.
- The installed build handles a provider failure and cancellation with truthful status and usable controls afterward.
- The local connector can read and update a disposable suite and inspect a real saved run without changing the user's normal suite or Codex configuration.

## Boundaries

Keep existing capabilities and saved data compatible. Do not add providers, API customizations, a new architecture, or exhaustive option-combination tests during stabilization. Private Cloud Compute entitlements, real Core AI model distribution, and Spotlight availability are separate platform/resource dependencies. The older feature checklist is a coverage inventory, not this release's exit gate.

Packaging, signing/notarization, store submission, and publishing need a chosen distribution route; this task prepares and verifies the local app without releasing it.

## Evidence

Verified on 5 September 2026 using the installed local debug build and a disposable copy of the acceptance suite. The user's normal suite and Codex configuration were not edited.

- `xcodebuild -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -destination 'platform=macOS' -only-testing:FoundationEvalsTests test` passed: 237 tests, zero failures, one optional Core AI fixture skipped. Parameterized cases account for 296 successful executions. This includes draft recovery, cancellation, systemic provider errors, field assertions, refusal timeout, and Spotlight recording drain.
- The final accessibility-only adjustment was rebuilt and checked in the native interface: advanced model options start collapsed, expand correctly, and preserve individual control accessibility identifiers. The XCUI test target was not run.
- Native scoring run `DAA6667E-36E5-40CB-8E77-0951D59AAA9F` passed the correct sky explanation and failed the deliberately false answer: two completed samples, zero execution issues. Filtering, trace inspection, saved history after relaunch, and JSON export worked; the exported JSON matched the stored run.
- An incomplete setup turn displayed “Draft saved on this Mac,” blocked execution, and survived relaunch without replacing the canonical valid suite. Completing the turn restored automatic saving and enabled Run.
- Native provider-failure run `59E77FEE-96DB-4B37-A29B-41650FEDBC38` stopped after one of four planned samples with `customProviderError` and no fabricated response.
- Native streaming run `7DE2C4B3-7251-4F30-BB28-7AB3F162F15B` displayed partial output, then recorded cancellation after the Cancel action. Its final response remained empty, later samples did not run, and the editor returned to an enabled Run action.
- Live authenticated MCP reads and replacements round-tripped a field assertion, preserved it when an older-style replacement omitted the field, and cleared it for an explicit empty array. Verification encountered intermittent Python HTTP-client read timeouts; subsequent curl requests completed. This establishes the successful operations, not a diagnosed or repaired transport-timeout cause.

The installed app passed strict code-signature verification. These checks establish local workflow readiness; they do not establish notarization, distribution, or every platform-dependent feature combination.
