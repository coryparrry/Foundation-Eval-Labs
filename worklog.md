# Worklog

- Goal: make the Suite Editor easier to navigate and faster to type in, hide PCC for the open-source surface, and show available reasoning context in results.
- Scope: existing SwiftUI view/data flow, provider visibility and migration, response transcript/usage traces, focused tests, and real-interface validation.
- Current: implementation and scoring-page correction complete and validated; ready to merge into local `main`.
- Steering: remove card/scroll friction and fix invalidation at the source; keep scoring targets on Scoring rather than Cases; keep dormant PCC code reusable; expose only reasoning data Apple actually returns, never opaque signatures.
- Boundary: Apple documents that current models may return reasoning token counts while textual reasoning segments are empty. PCC itself does not require app-managed login/API keys, but its managed entitlement and eligibility are unsuitable for the default open-source UI.
- Implemented: four editor pages, one selected case editor, compact result list/detail, single summary surface, 400 ms autosave debounce, on-device suite migration, readable subject/judge reasoning traces, and removal of the PCC entitlement/build path.
- Evidence: Xcode build-for-testing passed; 17/17 unit and UI tests passed; live macOS inspection confirmed compact result navigation and the Scoring page's selected-case prompt plus expected/required/reference input.
