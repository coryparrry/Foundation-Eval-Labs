# Workflow traces

Open a saved run and choose **Workflow trace**. Select a case and repetition, expand the span hierarchy, and select a row to inspect its timing, metadata, input/output or recorded sample transcript. **Report** retains the result dashboard, comparison, full response evidence and Apple feedback export tools.

The waterfall uses one time axis per sample. The sample includes preparation and scoring; the existing subject-request latency keeps its original meaning. A child bar uses its measured start offset, so overlapping tool calls stay overlapping. Nested durations are inclusive and must not be summed. The list and bars share the same rows and scrolling. Use Up/Down to select, Right to expand, and Left to collapse or select the parent. The divider resizes the details pane; narrow windows allow horizontal scrolling in the waterfall.

## What is recorded

| Evidence | Source and scope |
|---|---|
| Session setup, restoration, prompt preparation, history policy and prewarm request | App-observed monotonic timing around actual native operations. Prewarming records the request and configured lead wait, not unexposed background model work. |
| Setup turns and final generation | App-observed native request spans. Streaming first-visible-content latency is labelled separately; it is not a first-token or per-token timestamp. |
| Scoring and AI judge attempts | Separate spans for scoring, the judge and each generation attempt, with retained outcome/error evidence. |
| Custom and reference tools | Actual call start/end measurements and their generating parent. Failed, cancelled and bounded rejected calls remain inspectable. Existing reference query/output omissions are preserved. |
| Deliberate local HTTP tool requests | Nested request method, sanitized endpoint, response status when received, byte counts and observed duration. No new network requests are made for tracing. Headers and transport bodies are not added to trace metadata. |
| Token counts | `LanguageModelSession.Response.usage` and existing recorded usage. The installed Xcode 27 SDK marks this API as macOS 27; the app already targets macOS 27. Cached input is a subset of input, and reasoning is a subset of output. Failed generation spans do not inherit earlier setup-token totals. |
| Input/output and transcript | Existing captured evidence is joined by call/turn/attempt identity. Full transcript capture remains opt-in with the existing 4 MiB limit and omission handling. The inspector previews a bounded portion and exports the complete saved transcript. |

On-device Foundation Models inference is a native operation and requires no HTTP span. The app does not synthesize internal inference stages, network calls, hidden reasoning, token timestamps or costs. Built-in tool transcript entries do not expose app-observed offsets or turn identity in the saved aggregate; they appear at sample scope without timeline placement.

Apple also provides a separate [Foundation Models instrument](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app) for profiling. Its internal instrument data is not presented as though it were available through the app's runtime trace API. See Apple's [usage documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct).

## Saved-run compatibility

The new `workflowTrace` archive field is optional. Older runs retain their recorded durations, content, tool outcomes and exports, but receive no invented start offsets. Aggregate legacy tool calls stay at sample scope because the saved data does not identify their generating turn. Missing or invalid timing displays as unavailable.

Trace data remains part of the local run archive. No trace data is sent to Telemetry or added to the app's anonymous usage telemetry.
