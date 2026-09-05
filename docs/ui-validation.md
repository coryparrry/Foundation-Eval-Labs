# Native UI validation — 5 September 2026

The Computer UI walkthrough reproduced and verified fixes for:

- Selecting Failed on a mixed run, then opening a successful run retained the old filter and hid its results. Each run now starts with All and an empty search.
- A cancelled run with no collected responses displayed “No Matching Results.” It now explains that cancellation happened before collection and directs the user to Suite Editor.
- Baselines defaulted to the newest prior run even when its scoring mode was incompatible. Selection now chooses the newest compatible prior run, or No baseline. Picker labels include suite name, version, and seconds.
- The scoring footer incorrectly claimed reference equality bypassed the rubric. It now agrees with the judge policy and explains standalone exact-output requirements.

## Verification

- Xcode MCP `BuildProject`: succeeded.
- Xcode MCP `RunSomeTests`, `EvaluationRunAnalysisTests` and `RunBaselineSelectionTests`: 10 passed, 0 failed.
- `git diff --check`: passed.
- Installed Debug app: `codesign --verify --deep --strict` passed.
- Computer UI: mixed run → Failed → successful run reset to All and displayed its one result.
- Computer UI: unmatched search displayed “0 of 1”; Clear filters restored the result.
- Computer UI and screenshot: empty cancelled run displayed the new explanation without search/filter controls.
- Computer UI: successful run selected a compatible earlier run; mixed and cancelled runs with no compatible baseline selected No baseline.
- Computer UI: verified corrected scoring guidance and preservation of the original example prompt, reference answer, and rubric. Empty-prompt validation disabled Run during the walkthrough; the prompt was restored.
- Computer UI: started a fresh on-device AI-rubric evaluation. Run `DDBA31B3-EDFD-4502-801A-8FC503BF39F1` completed with one passed result, no issues, and a 3/4 score.
- Computer UI: exported that run as JSON; parsing confirmed the run ID and one result. Quit/relaunch preserved the new history entry and original suite.
- Independent read-only review of the result and scoring changes found no actionable issues.

This pass validates the listed paths; it is not an exhaustive test of every provider or tool configuration.
