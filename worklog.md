# Worklog

- Current task: completed the requested simple local MCP contract. Bearer authentication, Keychain storage, credential rotation, custom protocol dialects, and generated authorization headers are removed; loopback-only binding and host/origin checks remain.
- Evidence: 27 focused MCP/installer tests pass, including version negotiation and real loopback socket coverage. The final build launched as the sole `127.0.0.1:17873` listener. A fresh `codex exec` discovered `foundation-evals` and successfully called `eval_get_state`, returning “My Foundation Model Eval” at revision `e3b66ec47bf4dae6a2d159cfe9fc9ea194a3aac2e94d91a2fc51be4c70e62231`.

- Goal: add a Swift-native MCP connector so agents can configure suites, upload context, run/cancel evals, and read durable results without UI control.
- Current: App Sandbox and the folder picker are removed; Connect to Codex writes the managed block directly under `~/.codex`.
- Steering: never launch the installed and DerivedData builds together; fix the broken Suite Editor at its source, not with window-size workarounds.
- Contract: unauthenticated loopback HTTP on fixed port 17873; standard MCP `2025-06-18`; one active run; on-device model only.
- Integrity: durable writes before success, revision/resource-based idempotency, bounded requests/workloads, no caller file paths, cooperative cancellation, interrupted-run recovery.
- Installation: direct `~/.codex/config.toml` managed-block update containing only the loopback URL; reconnect required after changes; no folder picker.
- Evidence: the official Xcode build and build-for-testing both pass; all 53 unit tests pass, including the real-socket protocol test and new missing/symlinked `.codex` coverage. The rebuilt app has no App Sandbox, bookmark, user-selected-file, or network sandbox entitlement.
- Boundaries: the follow-up signed run and UI test hit Xcode 27 beta worker/automation stalls, although the live UI geometry was verified directly. The official conformance CLI has no bearer-header option, so it cannot drive this authenticated endpoint without weakening the production contract. Guided Codex acceptance still requires Keychain authorization for a newly signed build and a Codex restart.
- Signing: hardened runtime is enabled for both app configurations, but Xcode disables it for this checkout's ad-hoc “Sign to Run Locally” build. A Developer ID signature is required to verify the runtime flag and stable Keychain identity as distribution evidence.
- UI repair: commit `d501878` introduced `VStack { header; ScrollView { page } }`, causing a `1180×780` window to host a vertically centred `1180×1830` split view. Restoring one outer `ScrollView` preserves the tabbed editor and now produces matching `1180×780` window/split-view geometry with the MCP runtime connected.
- Launch diagnosis: LLDB reported `stop reason = breakpoint 1.1`; the breakpoint resolved to five async locations at the `startServer()` catch line even though `serverState` was `running` and the error payload was nil. Removing the persisted breakpoint restored normal execution; Xcode then reported the process running with no breakpoints set.
- Settings discovery: the MCP connector form remains in the macOS Settings scene. A native bottom-sidebar `SettingsLink` opens the one-action Connect to Codex workflow without competing with primary navigation.
- Startup UX: existing installations autostart from the app scene; Connect to Codex starts the server directly after committing configuration, avoiding the installation-state task race without blocking initial launch behind Keychain.
- Sidebar UX: the split view now has a real 250-point content floor and 280-point preferred width; MCP setup lives in a separated bottom utility row rather than a competing navigation section.
- Connector UX: port selection and its persisted reconfiguration path are removed; the app always uses `127.0.0.1:17873`, starts automatically after installation, and keeps manual recovery controls under Advanced.
- Acceptance fixes: existing Codex config modes are preserved; modern `ping` and undeclared tool arguments are rejected; editable UI drafts cannot replace the durable suite until validated and written; MCP state always rereads that one durable suite; active result bodies are checkpointed for MCP polling and crash recovery. Final build-for-testing passes; signed unit lane is 51 passed/1 intentional socket skip, and the unsigned real-socket protocol lane is 17/17.

## Previous completed work

- Goal: make the Suite Editor easier to navigate and faster to type in, hide PCC for the open-source surface, and show available reasoning context in results.
- Scope: existing SwiftUI view/data flow, provider visibility and migration, response transcript/usage traces, focused tests, and real-interface validation.
- Current: implementation and scoring-page correction complete and validated; ready to merge into local `main`.
- Steering: remove card/scroll friction and fix invalidation at the source; keep scoring targets on Scoring rather than Cases; keep dormant PCC code reusable; expose only reasoning data Apple actually returns, never opaque signatures.
- Boundary: Apple documents that current models may return reasoning token counts while textual reasoning segments are empty. PCC itself does not require app-managed login/API keys, but its managed entitlement and eligibility are unsuitable for the default open-source UI.
- Implemented: four editor pages, one selected case editor, compact result list/detail, single summary surface, 400 ms autosave debounce, on-device suite migration, readable subject/judge reasoning traces, and removal of the PCC entitlement/build path.
- Evidence: Xcode build-for-testing passed; 17/17 unit and UI tests passed; live macOS inspection confirmed compact result navigation and the Scoring page's selected-case prompt plus expected/required/reference input.
