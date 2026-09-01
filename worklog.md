# Worklog

- Goal: build a simple macOS SwiftUI app for running Apple Foundation Models evaluations without Xcode.
- Scope: instructions, prompts, file context, repeatable cases, response scoring, local traces, and export.
- Current: guided scoring modes, rubric templates, observable 1–4 judging, reference guidance, coverage-aware results, and traceable judge configuration are complete.
- Verified: Xcode build-for-testing passed with no warnings; 3/3 tests passed; preview rendered; live rubric scoring returned 4/4 with criterion-by-criterion rationale; oversized judge input returned an actionable unscored error.
- Steering: make scoring actually useful and make it obvious what belongs in each field; keep the app simple and use Xcode MCP.
