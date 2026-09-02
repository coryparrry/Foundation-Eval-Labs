# Worklog

- Goal: add a Swift-native MCP connector so agents can configure suites, upload context, run/cancel evals, and read durable results without UI control.
- Current: exposing the existing MCP settings/install workflow through a visible native Settings link in the main sidebar; final external Codex acceptance remains.
- Steering: never launch the installed and DerivedData builds together; fix the broken Suite Editor at its source, not with window-size workarounds.
- Contract: loopback HTTP on fixed port 17873; MCP 2026-07-28 plus Codex-compatible 2025-11-25; bearer auth; one active run; on-device model only.
- Integrity: durable writes before success, revision/resource-based idempotency, bounded requests/workloads, no caller file paths, cooperative cancellation, interrupted-run recovery.
- Installation: one-time sandbox folder grant, managed Codex TOML block, plaintext token disclosure, per-server approval mode, reconnect required after changes.
- Evidence: Xcode build-for-testing passes. The unsigned protocol lane passes 15/15, including real hostile/admission/socket/rebind checks. In the signed app-host lane, 45/46 passed and the socket client was correctly denied because the production app requests `network.server`, not `network.client`; that test now declares the sandbox precondition explicitly.
- Boundaries: the follow-up signed run and UI test hit Xcode 27 beta worker/automation stalls, although the live UI geometry was verified directly. The official conformance CLI has no bearer-header option, so it cannot drive this authenticated endpoint without weakening the production contract. Guided Codex acceptance still requires the one-time folder picker, Keychain authorization for a newly signed build, and restart.
- Signing: this checkout produces an ad-hoc development build. A stable distribution signature is required before treating Keychain identity across app rebuilds as release evidence.
- UI repair: commit `d501878` introduced `VStack { header; ScrollView { page } }`, causing a `1180×780` window to host a vertically centred `1180×1830` split view. Restoring one outer `ScrollView` preserves the tabbed editor and now produces matching `1180×780` window/split-view geometry with the MCP runtime connected.
- Launch diagnosis: LLDB reported `stop reason = breakpoint 1.1`; the breakpoint resolved to five async locations at the `startServer()` catch line even though `serverState` was `running` and the error payload was nil. Removing the persisted breakpoint restored normal execution; Xcode then reported the process running with no breakpoints set.
- Settings discovery: the complete MCP connector form existed only in the macOS Settings scene. A native `SettingsLink` near the top of the sidebar opens the existing Install in Codex workflow.
- Startup UX: MCP autostart runs only after the managed connector is installed; the keyed task starts it immediately when first-time installation succeeds, without blocking initial launch behind a Keychain dialog.
- Acceptance fixes: existing Codex config modes are preserved; modern `ping` and undeclared tool arguments are rejected; editable UI drafts cannot replace the durable suite until validated and written; MCP state always rereads that one durable suite; active result bodies are checkpointed for MCP polling and crash recovery. Final build-for-testing passes; signed unit lane is 51 passed/1 intentional socket skip, and the unsigned real-socket protocol lane is 17/17.

## Previous completed work

- Goal: make the Suite Editor easier to navigate and faster to type in, hide PCC for the open-source surface, and show available reasoning context in results.
- Scope: existing SwiftUI view/data flow, provider visibility and migration, response transcript/usage traces, focused tests, and real-interface validation.
- Current: implementation and scoring-page correction complete and validated; ready to merge into local `main`.
- Steering: remove card/scroll friction and fix invalidation at the source; keep scoring targets on Scoring rather than Cases; keep dormant PCC code reusable; expose only reasoning data Apple actually returns, never opaque signatures.
- Boundary: Apple documents that current models may return reasoning token counts while textual reasoning segments are empty. PCC itself does not require app-managed login/API keys, but its managed entitlement and eligibility are unsuitable for the default open-source UI.
- Implemented: four editor pages, one selected case editor, compact result list/detail, single summary surface, 400 ms autosave debounce, on-device suite migration, readable subject/judge reasoning traces, and removal of the PCC entitlement/build path.
- Evidence: Xcode build-for-testing passed; 17/17 unit and UI tests passed; live macOS inspection confirmed compact result navigation and the Scoring page's selected-case prompt plus expected/required/reference input.
