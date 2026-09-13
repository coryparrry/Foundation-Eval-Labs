# Development workflow implementation report

## Outcome

The backend workflow is implemented for project/suite persistence, migration,
independent judging, reassessment and human evidence, repository snapshots,
controlled instruction experiments, MCP automation, the running-app CLI, and
fail-closed release reports.

The backend is integrated with the project frontend and the workflow trace UI
from current main. Projects and suites remain visible in the sidebar, run history
is searchable, and the suite editor exposes Cases, Results, Compare, and Configure.
Experiments live under Compare; judge connections and evidence approvals have
dedicated settings and current-configuration approval checks.

## Combined integration verification

- Generated the non-UI scheme with `python3 script/ci_core_scheme.py`.
- `xcodebuild -quiet -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvalsCoreCI -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/FoundationEvals-frontend-build -parallel-testing-enabled NO -only-testing:FoundationEvalsTests CODE_SIGNING_ALLOWED=NO test` — 356 passed, one skipped, zero failed.
- A standalone macOS Debug build also passed with code signing disabled.
- Independent integration review findings were fixed and rechecked: report rows
  and settings follow the selected assessment, overview ordering follows durable
  run history, and clearing history removes copied image evidence with retryable
  deletion state. Regression coverage includes cleanup failures and retry after
  reopening the store.
- Native manual inspection used an isolated app identity and sample storage with
  telemetry and MCP autostart disabled. An on-device evaluation completed; the
  project navigation, searchable history, and populated workflow trace were
  inspected. Native controls disconnected before the report inspection could
  finish; the preview process remained running and no app crash was observed.
- Automated UI tests and paid/live external judge-provider calls were not run.

## Backend verification

- `xcodebuild -quiet -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:FoundationEvalsTests` — passed.
- `xcodebuild -quiet -project FoundationEvals/FoundationEvals.xcodeproj -scheme FoundationEvals -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` — passed after the final review fixes.
- Focused workflow, compatible-judge, persistence, field-assertion, MCP protocol, and MCP store-authority groups — passed.
- `script/foundation-evals --help` — passed with exit 0.
- Invalid CLI timeout and endpoint inputs — rejected before transport with the documented execution-error exit 30.
- `git diff --check` — passed.

The HTTP judge evidence uses a local deterministic fixture. No paid external
provider call, live running-app CLI session, native visual inspection, or UI
test pass is claimed.

## Backend correction closure

| Review item | Backend resolution and regression evidence |
|---|---|
| R1 | Release decisions bind current and approved assessments to the same cases, rubric, judge prompt version, and passing score. Easier-rubric reassessments fail closed. |
| R2 | Every new run owns an integrity-checked subject-evidence snapshot. Reassessment and judge checks replay the original instructions, cases, and image bytes even after current attachments are removed. |
| R3 | Experiment variants retain their actual definition revisions; release checks reject a candidate before adoption and accept its fresh revision after adoption. |
| R4 | Baseline compatibility excludes the subject instructions/model being compared while retaining exact case and scoring compatibility checks. Instruction-only changes compare; case/rubric changes do not. |
| R5 | Summary, analysis, comparison, error, usage, critical-case, and release consumers share the selected assessment projection without mutating subject results. |
| R6 | Reassessment and judge-check activity blocks workspace changes until captured work finishes, preventing cross-suite loss or attribution. |
| R7 | Experiment recommendations require complete, error-free, fully scored coverage for every case and repetition. Error-dominated, missing, and unscored candidates request more evidence. |
| R8 | `eval_check` resolves an existing owned operation before busy validation and rejects project, suite, or revision conflicts. |
| R9 | Run lookup and deletion resolve persisted ownership across the workspace catalog, so polling survives UI suite changes. |
| R10 | `EvaluationStore.runFeatureAdapter` executes shared application code and persists a normal run that supports reload, reassessment, comparison, baseline approval, and release checks. |
| R11 | `eval_project_release_report` aggregates all required suites and fails closed for missing, failed, stale, or incompatible evidence. Durable run ordering identifies the actual latest run. |
| R12 | The structured-extraction schema includes `subtotal` and `discount`; tests verify every expected JSON key and assertion is represented. |

## Independent review

The backend received an independent read-only review. Its findings were fixed
and covered where practical: failed workspace switches roll back, reassessment
reapplies field assertions, disclosure approval is bound to the destination and
model/provider configuration, release checks reject unscored evidence and
invalid thresholds, structured starters are runnable, mixed judge identities
fail closed, and MCP mutation annotations are accurate. The final pass also
verified that project reports resolve nonselected repository definitions without
mutating storage, failed evidence deletion retains a retry path, and scoring
contracts ignore editor-only labels and nested IDs while preserving semantic
case compatibility.

## Delivery boundary

The combined implementation is on `codex/project-workflow-frontend`. Integration
does not publish a release or merge that branch into main. UI tests remain stopped
at the user's instruction; unit coverage is separate from the native inspection
described above.
