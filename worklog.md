# Workspace reset controls

- Request: add ways to clear previous traces and reset the current evaluation suite.
- Added a toolbar menu with suite reset, history clearing, and combined reset; each requires an explicit destructive confirmation and is disabled during active operations.
- Blank suites persist canonically while execution still requires a prompt. History clearing removes stored JSON and obsolete recovery markers, and reloads history even after partial deletion failure.
- Verified: Xcode BuildProject(buildForTesting: true); four WorkspaceResetTests; WorkflowTraceUITests/testWorkspaceResetConfirmationAndPersistence(); git diff --check. All targeted tests passed after fixing test-fixture setup and macOS sheet lookup.
- Inspected the native reset screenshot; Xcode RunProject launched the updated app successfully.

# Typing latency

- Request: diagnose and fix extreme lag while typing.
- Live before sample showed repeated main-thread Foundation Models context-size queries waiting on a semaphore during validation/rendering and synchronous suite saves on each edit.
- Cache context size by use case and guardrails; refresh on activation and before a run. Autosave after a 350 ms pause, observe the draft outside the navigation root, and flush on deactivation, closing, quitting, running, and revision-sensitive operations.
- Independent review found a pending-edit/MCP replacement race; flushing before revision checks fixes it, with a regression test proving local text survives a stale remote replacement.
- Verified 16 distinct targeted tests: five EditorPerformanceTests, four WorkspaceResetTests, five EvaluationStorePersistenceTests, and native typing/quit/relaunch plus reset UI tests. All passed. Xcode build/run and git diff --check passed.
- Repeated live prompt probe in the same layout with 39 saved runs. CUA operation duration was 18.8 s before and 3.94 s after (includes automation overhead, not a per-keystroke benchmark). Twenty-second stack samples showed context-size samples 491 -> 26 and saveSuite samples 460 -> 3; the remaining initial metadata refresh is expected. Samples are local under /tmp/foundation-typing-active-{before,after}.sample.txt.
- Updated app launched; temporary probe text removed and original prompt restored.

# Prompt-specific editing performance

- User clarified that the prompt box remained sluggish. Isolated prompt editing in a leaf SwiftUI view with local text state; each edit synchronously reaches a store-owned pending buffer without publishing the whole suite. Existing save/run/quit/revision boundaries flush the buffer.
- Kept the standard TextEditor after live testing showed a native replacement alone did not address the shared-state redraws. Selection tracking now observes case identity outside the outer editor layout.
- Pending prompts are merged before duplication/saving, discarded only after successful reset, and protected from stale remote writes. Independent review checked the synchronization/data-loss boundaries; removed a save-skipping optimization that could resurrect an older incomplete draft.
- Regression coverage now directly types multiline prompts, deletes/undoes, switches cases, and quits/reopens. The case-picker test waits for async saving to finish before testing selection.
- Live final prompt probe: 2.21 s for the CUA action sequence versus 3.94 s after the first lag fix (automation overhead included; not a per-keystroke benchmark). Twenty-second process samples showed NSHostingView.layout samples 380 -> 258. Final sample: /tmp/foundation-isolated-prompt-after.sample.txt. Temporary probe text was removed.
- Verification: six EditorPerformanceTests, four WorkspaceResetTests, two PromptTextEditorTests, and two targeted WorkflowTraceUITests passed across targeted Xcode runs. git diff --check passed. A redundant final UI rerun was stopped at the user’s request; its result bundle was incomplete.
- User requested an end to UI tests because they repeatedly took over the screen. Stopped the active Xcode app/test session; do not run further UI tests or control apps unless the user asks.

# Workflow timeline clarity

- Request: correct the misleading appearance of sequential setup spans starting together.
- Removed minimum-duration bar inflation. Subpixel durations use a labeled diamond marker, parent intervals use outlines, every row shows a start offset, and Fit/10×/100×/1,000× zoom exposes short intervals without changing recorded timing.
- Added deterministic interval placement and regression tests for sequential subpixel spans, zoom scaling, zero durations, and invalid timing. Included these tests in the portable Swift package.
- Verified Xcode BuildProject(buildForTesting: true) succeeds and swift test --scratch-path /tmp/foundation-timeline-build --filter WorkflowTimelineIntervalTests passes 2 tests. The default SwiftPM build directory hit Finder metadata signing errors; the clean temporary build succeeded. git diff --check passed. Independent scoped review found no further issues after correcting zoom sizing.
- No UI tests, app launch, or screen control performed. The new native layout has compiled but has not been visually inspected; the currently running app retains its previous build until relaunched.

# Span disclosure hit targets

- User requests launching the new app after each fix; continue avoiding UI tests unless asked.
- Expanded parent-span disclosure buttons to include the icon, title, and full label area. Clicking selects the parent and toggles expansion; leaves remain ordinary selectable rows.
- Verified Xcode RunProject built without errors and launched the updated app. git diff --check passed. No UI tests were run for this hit-area change.
