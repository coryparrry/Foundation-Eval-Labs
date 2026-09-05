# Validated judge evidence and trace coverage

Unambiguous exact-output requirements are checked directly in Swift, before any AI grading. The supported complete-line forms are:

```text
exact: "DELIVERY VERIFIED"
The final response is exactly "DELIVERY VERIFIED".
The response is exactly "DELIVERY VERIFIED".
```

JSON strings support Unicode, punctuation and escaped whitespace. The two sentence forms also accept conservative unquoted uppercase status literals, such as the original `The final response is exactly DELIVERY VERIFIED.` The shorthand allows only one to eight uppercase ASCII words/numbers with spaces, underscores or hyphens, up to 256 characters; logical words such as AND, OR, IF and UNLESS exclude it. Other prose is not silently converted into an exact test. Quote other literal values or use `exact:` with a JSON string.

Exact rules compare the whole response without trimming, case folding or punctuation changes. They receive 4 for a match and 1 for a mismatch. When every requirement is exact, no model judge is called. For mixed rubrics, only the remaining requirements go to the AI judge; the report records how its check indexes map back to the original rubric. The lowest score across all requirements determines the result, so a literal match cannot hide a failed tool or semantic requirement.

The AI judge returns one structured check per remaining requirement, with its score, explanation, and any claimed exact comparison of the complete response. The app requires complete, unique criterion coverage, scores in range, explanations, and expected comparison text grounded in that requirement or the supplied reference. Swift verifies each declared equality against the actual candidate.

A contradictory exact comparison permits one correction in a fresh session, supplied with equality facts calculated by Swift. Both attempts remain in the trace; their token usage is added together. A second contradiction, malformed evidence, or a correction that cannot fit the context budget stops scoring. Inconsistent or incomplete evidence produces **Unscored** with `invalidJudgeOutput`. It is not counted as a genuine failed evaluation. The overall accepted score is the lowest criterion score: a literal match cannot override a separately failed tool, format or factual requirement. A response matching the reference no longer bypasses the entire rubric. Use the existing Exact text scoring mode when equality is the whole evaluation contract.

The model still interprets free-text requirements and selects its evidence. These checks reject declared contradictions; they do not make every semantic judgment correct or guarantee that the model declares every incorrect prose claim. Historical reports keep their original scores. The new judge prompt version prevents treating old and new judging policies as an unchanged comparison contract.

Each new evaluation records **Scoring evidence** in the result UI and JSON/MCP report:

- Exact judge instructions and composed input.
- Raw structured verdicts and exact inputs for both the original and any correction attempt.
- Validated per-requirement evidence, when validation succeeds.
- Validation or execution errors and available judge usage.

This is the judge's supplied evidence and explanation, not private model reasoning. Image payloads remain represented by the run's existing attachment metadata.

## Can the app obtain full traces?

Yes, at the public API boundary. Apple's [`LanguageModelSession.transcript`](https://developer.apple.com/documentation/foundationmodels/inspecting-session-transcripts-and-reporting-model-feedback) exposes instructions, prompts, responses, tools and outputs, and reasoning entries when the model supplies them. `Transcript` conforms to `Codable` in the installed SDK, so a complete public transcript can be serialized. Dynamic session history excludes its leading dynamic instructions, so configuration and profile transition evidence must accompany it when reconstructing what was active at each step.

For failure capture, [`preserveTranscript`](https://developer.apple.com/documentation/foundationmodels/transcripterrorhandlingpolicy/preservetranscript) keeps the current transcript, which may end with partially generated content. Reverted history cannot supply a failed request's discarded content afterward.

[The Foundation Models instrument](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app) provides performance traces for requests, tool calls, asset loading, durations and token/cache metrics. This is a separate Instruments recording, not the app's JSON report.

The app currently persists selected subject response/tool/profile/timing fields and the detailed judge evidence above. It does not yet persist the complete public subject transcript or an Instruments recording. Old runs cannot recover fields that were never saved. Reference tool queries and returned passages remain intentionally excluded from current reports. Full transcript capture would need an explicit trace-content setting to change that behavior, plus attachment-aware export and capture during errors.

Neither API provides arbitrary hidden model internals or reasoning that the provider does not expose. Opaque reasoning signatures are not readable reasoning.

Apple sources were checked through Xcode MCP and the Xcode 27 beta 6 interface on 2026-09-05.
