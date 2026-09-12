# Development workflow implementation checklist

This is the durable acceptance ledger for the project/suite, independent-judge,
development-integration, experiment, and release-check implementation. A checked
item means the implementation and its relevant automated evidence are present;
native inspection and real-provider limitations are recorded separately below.

## Workspace and migration

- [x] Versioned workspace catalog with stable project and suite IDs.
- [x] Create, duplicate, rename, archive, and switch projects and suites.
- [x] Autosaved suite drafts remain isolated across switches.
- [x] Attachments, runs, active operations, and baselines are suite-owned.
- [x] Existing suite, draft, attachments, active run, and history migrate without destructive moves.
- [ ] Project overview reports stale definitions and latest check state.
- [ ] Cases, Results, and Compare are primary navigation; advanced controls are secondary.
- [x] Complete structured-extraction, grounded-answer, and conversation starter suites.
- [x] CSV/JSONL case import supports mapping, preview, size bounds, and actionable validation.

## Independent judging and approval

- [x] Per-suite judge selection supports same-model, local compatible, OpenRouter, and custom compatible connections.
- [x] Connections have explicit base URL/model/capabilities and a connection check.
- [x] API keys use Keychain and are excluded from suites, exports, reports, and logs.
- [x] Compatible Chat Completions client validates structured verdicts and fails closed.
- [x] Multimodal/structured-output requirements are capability checked, never silently omitted.
- [x] External disclosure previews the exact evidence categories sent, binds approval to the connection/model/provider configuration, and requires explicit suite opt-in.
- [x] Judges never receive application tool access and untrusted evidence is delimited.
- [x] Timeout, missing, malformed, and exhausted corrections remain unscored errors.
- [x] Saved responses can be reassessed without generation; all assessments remain attached to the run.
- [x] Reports identify the selected assessment and changed or mixed judge conditions.
- [x] Judge identity, prompt/rubric version, settings, provenance, usage, duration, and cost availability are separate from subject execution.
- [x] Human correction preserves the original judgment and records reason/reviewer/time.
- [x] Reviewed examples can be collected and run as judge checks against known good/bad responses.
- [x] AI scores never mutate expected answers or approve baselines.
- [x] Baseline approval targets an eligible completed run plus assessment and preserves history.

## Development integration

- [x] Optional repository links use one authoritative, versioned suite definition with explicit conflict handling.
- [x] Runs snapshot immutable definitions/evidence, repository commit, and working-tree dirtiness.
- [x] Generated responses/traces remain local; repository fixtures require explicit export.
- [x] Feature adapter and runnable Swift shared-code example reuse the scoring/reporting engine.
- [x] MCP operations target explicit project/suite IDs rather than relying on current UI selection.
- [x] `foundation-evals check --project ... --suite ...` implements the running-app control and release-report protocol.

## Controlled experiments

- [x] Two-variant shared-instruction experiments freeze cases, scoring, and judge configuration.
- [x] Exact variant change and balanced execution order are retained.
- [x] Per-case improvements/regressions, latency, coverage, and changed conditions are reported.
- [x] Case-aware uncertainty does not treat repeated trials as independent cases.
- [x] Outcome can be keep-current, adopt-candidate, collect-more-evidence, or inconclusive.

## Release checks

- [x] Required suites, critical cases, bounded error/latency limits, and approved-baseline comparisons are supported.
- [x] Machine-readable and human-readable reports share the same decision.
- [x] Exit statuses distinguish pass, regression, incomplete/incompatible evidence, and execution error.
- [x] Missing, stale, unscored, mixed-judge, or incompatible evidence fails closed.
- [x] Standalone/headless CI, cloud accounts, collaboration, and extra subject providers remain explicitly deferred.

## Verification evidence

- [x] Migration and suite/draft/attachment/history isolation tests.
- [x] Interrupted-run recovery, concurrent UI/MCP edit, and wrong-revision tests.
- [x] Judge failure, invalid evidence, reassessment, correction, and baseline provenance tests.
- [x] Repository edit/conflict and dirty-working-tree tests.
- [x] Feature adapter, CLI/protocol, import, experiment, and release-check tests.
- [x] Focused backend tests pass.
- [x] Full non-UI build and backend test target pass.
- [ ] Native UI is launched and inspected.
- [x] Independent review completed and material findings verified/fixed.

## Explicit validation boundaries

- Real paid compatible endpoints are tested only when existing credentials are available and use is authorized.
- Local fixture HTTP services provide deterministic protocol, timeout, malformed-response, and capability evidence.
- The initial CLI requires the running macOS app. No Linux/headless/standalone CI support is claimed.
- Live running-app CLI execution was not performed; parser behavior and MCP protocol/store authority are covered independently.
- Frontend completion, native visual inspection, and UI-test cleanup are assigned to Astra. UI tests were stopped at the user's instruction and no UI pass is claimed here.
