# Evaluation and tracing design

## Product workflow

Foundation Evals should help a developer define a task, measure it repeatedly, inspect failures, change the prompt or generation settings, and compare the result against a saved baseline. The app remains a local macOS utility using Foundation Models; it does not require the Xcode-only Evaluations framework at runtime.

The existing app already provides fresh sessions per case, bounded references, deterministic checks, a structured rubric judge, durable runs, and agent control. The highest-value missing link is analysis across those saved runs. A larger catalogue of models or a remote telemetry backend would not close that gap.

## Decisions

1. **Build run analysis and baseline comparison.** Keep case identity stable and compare unchanged inputs and expected answers under the same scoring contract. Report scored denominators, missing samples, and incompatible evidence. A change in observed pass rate is descriptive, not proof of statistical significance. Repeated samples reveal inconsistency; errors and unscored samples must not become passing checks.
2. **Extend local execution traces.** Measure actual execution stages and tool durations. Preserve subject and judge token usage separately. Older reports must remain readable, with absent measurements shown as unavailable. Keep reference queries and returned passages out of saved tool metadata. Use Instruments for deeper framework internals; app-owned traces are not an Instruments export.
3. **Expose analysis through MCP.** Provide the same computed results to agents and the UI. Analysis should read saved runs without model execution, suite mutation, or sending data to another service. Keep the existing simple loopback contract and correct protocol defects with targeted tests.

## Evaluation practice

Choose deterministic checks for objective requirements. Use a rubric for qualities that cannot be checked directly, with a small set of observable requirements and human-reviewed examples to calibrate the judge. The same on-device model acting as both subject and judge can share biases; an AI verdict is not independent ground truth.

Build cases from representative real inputs, boundary conditions, malformed requests, and observed failures. Keep a held-out set when tuning prompts. Synthetic cases can expand coverage but need validation and should not replace deliberately difficult human-written examples.

Compare quality alongside completion, errors, latency, and token consumption. A high pass rate among a small scored subset is not high workload reliability. OS/model changes and different reference context can confound comparisons and should remain visible in run configuration.

## Deferred opportunities

- Human annotations and judge calibration reports need an explicit review data model.
- Multiple assertions and structured-output grading need a versioned scoring contract rather than adding ambiguous string checks.
- Importing traces from another app needs a documented ingestion schema and a clear separation between observed production traces and controlled evaluations.
- OpenTelemetry export is useful for interoperability, but adopting its evolving GenAI conventions and a backend is unnecessary for the current local workflow. Do not label app JSON as OTLP.
- Multi-turn scenarios and direct ingestion of another app’s traces still need their own execution and scoring contracts. Custom fixture/HTTP tools, dynamic profiles, guided output, and performance modes are now implemented; see [Foundation Models experiments](foundation-model-features.md).

## Research sources

Apple documentation was read through Xcode MCP on 2026-09-05:

- [Evaluating prompts](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses): iterative measurement, failure analysis, and regression checks.
- [Evaluating language model responses](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses): dataset, subject, evaluators, aggregate results.
- [Designing datasets](https://developer.apple.com/documentation/evaluations/designing-evaluation-datasets): representative coverage and synthetic-data limitations.
- [Designing effective model judges](https://developer.apple.com/documentation/evaluations/designing-effective-model-judges): calibration and judge biases.
- [Analyzing runtime performance](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app): request/tool durations and token accounting.

Additional primary sources:

- [Anthropic: Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents): repeated trials, grader selection, and distinguishing traces from final outcomes.
- [OpenTelemetry GenAI attributes](https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/): interoperable telemetry vocabulary; conventions have moved to a dedicated GenAI repository.

These decisions apply to this bounded improvement pass, not a claim that all possible evaluation workflows are complete.
