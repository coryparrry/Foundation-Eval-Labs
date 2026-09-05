# Validated judge evidence and trace coverage

Unambiguous exact-output requirements are checked directly in Swift, before any AI grading. The supported complete-line forms are:

```text
exact: "DELIVERY VERIFIED"
The final response is exactly "DELIVERY VERIFIED".
The response is exactly "DELIVERY VERIFIED".
```

JSON strings support Unicode, punctuation and escaped whitespace. The two sentence forms also accept conservative unquoted uppercase status literals, such as the original `The final response is exactly DELIVERY VERIFIED.` The shorthand allows only one to eight uppercase ASCII words/numbers with spaces, underscores or hyphens, up to 256 characters; logical words such as AND, OR, IF and UNLESS exclude it. Other prose is not silently converted into an exact test. Quote other literal values or use `exact:` with a JSON string.

Exact rules compare the whole response without trimming, case folding or punctuation changes. They receive 4 for a match and 1 for a mismatch. When every requirement is exact, no model judge is called. For mixed rubrics, only the remaining requirements go to the AI judge; the report records how its check indexes map back to the original rubric. The lowest score across all requirements determines the result, so a literal match cannot hide a failed tool or semantic requirement.

The AI judge receives a dynamic schema with a required named field for each remaining requirement. Each field contains a score and a short explanation. The application assigns the criterion indexes, then requires every assessment, a score from 1 to 4, and a non-empty explanation. Schema guidance is included explicitly in the request and counted in both admission and runtime context budgets.

The generation schema does not request literal-comparison arrays. Those fields caused the on-device model to invent irrelevant comparisons for semantic tasks and sometimes exhaust its output budget completing empty arrays. Recognized standalone exact rules continue to use Swift equality. Compound or unrecognized exact requirements remain model-scored; their equality claims are not independently guaranteed. The decoder still validates any unexpected supplied comparison evidence instead of ignoring it.

A rejected assessment permits one repair in a fresh session with the validation failure supplied as feedback. Unexpected contradictory comparison evidence uses application-computed equality facts. Both attempts remain in the trace and their token usage is added together. A second invalid assessment or a repair that cannot fit the context budget stops scoring. Inconsistent or incomplete evidence produces **Unscored** with `invalidJudgeOutput`, not a genuine failed evaluation or a fabricated pass. Model execution failures retain their own error categories. A response matching the reference never bypasses the entire rubric.

The model still interprets free-text requirements. Structural validation does not make every semantic score or explanation correct. Historical reports keep their original scores. The new judge prompt version prevents treating old and new judging policies as an unchanged comparison contract.

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

## End-to-end regression verification — 2026-09-05

The reported run `9FF20D93-91BA-4678-97DD-48BA9CB38E9F` generated its subject response successfully but returned only two of three judge checks. Intermediate live tests also exposed spurious literal comparisons and incomplete comparison arrays; prompt changes alone did not resolve them. The accepted configuration uses required named scalar assessments and keeps recognized standalone exact rules in application code.

Official Xcode MCP `RunAllTests` on the final Swift changes: **175 passed, 0 failed, 0 skipped**. An independent read-only review found no outstanding code findings. `git diff --check` passed.

| Live scenario | Saved run | Observed result |
|---|---|---|
| Original sky rubric, three repetitions | `B434BE7B-519E-4554-BB61-86F470D62C54` | 3/3 passed, all three requirements scored per response, no judge errors |
| Incorrect answer, four requirements | `0DAB9336-CC02-40FC-9F40-4FBA73E5BA7A` | Berlin-as-France-capital candidate failed with score 1; four assessments recorded |
| Mixed exact and semantic tool rubric | `5BF23A4F-EF02-408A-B30C-9E7FF17070D0` | Score 4; actual fixture call, profile transition and streamed response; original indexes preserved |
| Exact pass and mismatch | `BFE34888-A58A-430A-A90C-AB25C6965630` | READY passed with 4, OTHER failed with 1; neither used a model judge |
| Local HTTP, guided output and streaming | `E3738CF6-483D-49DE-8CD5-8748BA3151D6` | Actual HTTP POST recorded; structured delivered status passed |
| Unavailable HTTP endpoint | `DA720853-7BC1-48EC-A829-1964F766DF14` | Connection error and failed tool trace preserved; no fabricated pass |
| Imported text and reference lookup | `173BC64F-750D-4F29-B35F-2D0047CF981E` | Actual reference-tool call returned the supplied verification code; passed |
| Cancellation | `C92274DA-DFDA-4BBF-82A6-82CC0FDC40C9` | Terminal cancelled state, no active run left |
| Final installed app, primary Run button | `62F3BAC5-C519-4EC8-9DA6-A01AB9873EC4` | Original suite passed with three assessments and zero issues; JSON export and MCP agree after restart |

The installed app passed `codesign --verify --strict --deep`. Its executable debug library SHA-256 matched the final Xcode product: `dad7d69da34b4f567a2c478987dad72d1cd9b712e85bed6aa258150e67423cf7`. After restart, the installed app was the sole app instance and owned the loopback MCP listener. The UI showed the saved successful result and a comparable baseline against the three-repetition run. The original suite revision and empty attachment set were restored, and the temporary HTTP test server was stopped.

These checks establish the exercised on-device workflows, not universal semantic grading accuracy. The negative test also showed the model can let one factual failure influence another criterion's explanation. Calibrate subjective rubrics before using their scores as release gates. Private Cloud Compute and image/PDF ingestion were not exercised in this live matrix.
