# Development workflow backend implementation report

## Outcome

The backend workflow is implemented for project/suite persistence, migration,
independent judging, reassessment and human evidence, repository snapshots,
controlled instruction experiments, MCP automation, the running-app CLI, and
fail-closed release reports.

Frontend completion is deliberately not claimed. Astra owns the remaining UI
implementation, native visual inspection, and UI-test cleanup.

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

## Independent review

The backend received an independent read-only review. Its findings were fixed
and covered where practical: failed workspace switches roll back, reassessment
reapplies field assertions, disclosure approval is bound to the destination and
model/provider configuration, release checks reject unscored evidence and
invalid thresholds, structured starters are runnable, mixed judge identities
fail closed, and MCP mutation annotations are accurate.

## Astra handoff

- Finish the project overview and primary navigation surfaces.
- Render stale disclosure approval using the bound connection digest, not only
  the approval timestamp.
- Complete native interaction and visual QA.
- Repair and rerun the UI-test target. The earlier UI run was stopped at the
  user's instruction, so backend evidence must not be presented as UI evidence.
