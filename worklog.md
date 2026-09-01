# Worklog

- Goal: add truthful Foundation Models controls for provider, reasoning, context, generation, and read-only reference-tool use.
- Scope: suite configuration, provider admission/capabilities, bounded local tool calling, provider-aligned judging, context budgeting, trace persistence, result inspection, focused tests, and real-runtime validation.
- Current: implementation and final review fixes complete on `codex/model-controls-tools`; final reconciliation and commit in progress.
- Baseline: clean `main` at `24cc10e`; previous UI refinement passed three unit tests, one UI test, launch verification, and strict bundle signature verification.
- Steering: preserve evaluator semantics and editable scoring values; expose only real SDK capabilities; keep tools read-only and bounded; never hide provider, quota, context, or fallback behavior.
- Verified facts: the current on-device runtime reports tool calling, guided generation, vision, and an 8,192-token context but no reasoning capability; PCC reports reasoning, tools, guided generation, vision, and a 32,768-token context, with a managed-entitlement, network, and quota boundary.
- Validation: 12 unit tests and 1 UI test pass; Debug build/launch verification and unsigned Release compilation pass; the Debug artifact has no PCC entitlement; a temporary live on-device tool + fixed-judge round trip passed; final diff, script syntax, and entitlement checks pass.
- Boundary: no Apple Development signing identity is installed, so a signed PCC request was not attempted; `--pcc` now provides the explicit entitled Release path for approved identities.
