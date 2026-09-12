# Evaluate application feature code

`EvaluationFeatureAdapterRunner` exercises a real Swift feature entry point
without routing the request through Foundation Models. It produces the same
`EvaluationRun` consumed by analysis and release checks.

```swift
let adapter = ClosureFeatureAdapter(displayName: "Search summary") { input in
    try await SearchFeature.shared.summary(
        instructions: input.instructions,
        query: input.prompt
    )
}

let run = await EvaluationFeatureAdapterRunner().run(
    suiteRevision: savedRevision,
    suite: suite,
    adapter: adapter
)

let report = EvaluationReleaseCheckEvaluator.report(
    projectID: projectID,
    suite: suite,
    currentSuiteRevision: savedRevision,
    run: run,
    baseline: approvedBaselineRun,
    approvedBaseline: approval
)
exit(report.outcome.rawValue)
```

The example is compiled and executed by `EvaluationDevelopmentWorkflowTests`.
Exact-match and contains-text suites are scored directly. Review suites remain
unscored unless they contain deterministic JSON field assertions; model-judge
suites remain unscored until a complete assessment exists. Release checks fail
closed rather than treating missing judgment as a pass.
