# Worklog

- Goal: make AI-rubric scoring respect only the suite's explicit requirements and application-owned reference evidence.
- Scope: deterministic exact-reference scoring, escaped judge inputs, prompt-version traceability, focused tests, and real-runtime validation.
- Current: root-cause fix and final review corrections are complete on `codex/model-controls-tools`.
- Steering: a probabilistic judge must not overrule an exact application-owned reference match.
- Validation: all 13 unit tests pass against Xcode 27. A temporary UI run of the persisted `Every answer is cory` suite passed, and trace `52D18B7F-D14D-4949-A90D-A3172485C9FA` records three 4/4 passes with no judge calls or errors.
- Boundary: this task's saved project path is stale (`Documents/ChatGPT/...`); the live clean checkout is `/Users/coryparry/Documents/Projects/Apples-Foundation-Evals`. Xcode MCP is disabled on the host, so the implementation stays within already reviewed Foundation Models APIs and will be compiled against the installed Xcode 27 SDK.
