# Foundation Models experiments

The Features page configures real Foundation Models APIs. Configuration is saved with the suite and snapshotted in each run. Old suites open with these features disabled. MCP clients can supply `suite.features` to `eval_replace_suite`; omitting it preserves the existing configuration. `eval_get_state` returns the full declaration and limits; `eval_get_run` returns feature traces.

See [Custom local provider protocol](custom-provider-protocol.md) to implement the version 1 HTTP request and NDJSON response contract for a developer-owned model backend.

## Try a custom tool and profile

1. Open **Features → Tools → Add Sample**. This creates `lookupOrder` with a string `orderID` argument and a saved fixture response. Fixtures return the same response for every call; they are useful for repeatable tool-selection experiments.
2. Set a case prompt to `What is the status of order A-104?`. Choose Contains text scoring with expected text `shipped` for the sample fixture.
3. In **Profile**, enable the profile and require a tool first. Set after-tool instructions to `Use the returned order status in the final answer.`
4. In **Output**, add a string field named `status`. The app builds a runtime `GenerationSchema` and uses guided generation; it does not merely ask the model to format JSON.
5. Run the suite. Expand the sample's feature trace to inspect generated arguments, output, call outcome and duration, and actual profile activation events.

The profile uses Apple's `DynamicProfile` and session properties. Initially the configured tools are available. After the first tool output, it appends the after-tool instructions, removes tools, and disables further tool calls. This provides an exit from required-tool mode. The AI rubric judge receives the effective instructions after a transition. Concurrent calls already issued by the model may finish before the profile switches; the per-sample call limit still applies.

## Run your own implementation

A custom tool can call a developer-owned local HTTP service. To try the included example:

```sh
python3 examples/order_tool_server.py
```

Change the sample tool's execution mode to **Local HTTP**, set its endpoint to `http://127.0.0.1:19000/tool`, and change the expected status to `delivered`. The server derives its response from the generated `orderID`, so this exercises actual execution rather than a saved fixture.

The app sends:

```json
{"toolName":"lookupOrder","arguments":{"orderID":"A-104"}}
```

Return a successful HTTP status and a UTF-8 text or JSON body. The implementation may be written in Swift or any language. This bridge does not load an arbitrary Swift `Tool` type from another app; describe its arguments in the editor and implement the HTTP handler around your code.

Endpoints must use literal `http://127.0.0.1:<port>/...`; the app's MCP port, credentials, query strings and fragments are rejected. Redirects, proxies, cookies and response caching are disabled. Requests are limited to 16 KiB and 256 argument tokens, responses to 4 KiB and 512 model tokens, and the request timeout is ten seconds. Custom, reference, image, and search tools share the selected per-sample call allowance, including setup turns. Custom arguments and outputs are saved locally in reports; avoid putting secrets in fixtures or responses.

## Performance and interpretation

**Streaming** consumes aggregate partial snapshots and records the time to the first nonempty response content. This is not an exact first-token measurement. The running suite displays available partial text or guided output with case and repetition identity. Final response, token usage and transcript reasoning are collected from the completed stream. A cancelled or failed stream is recorded as such; partial content is not scored as a completed answer. Consult the acceptance checklist for the provider and output combinations verified in the native app.

**Prewarm** asks the framework to prepare the session before input token counting. It is a hint, not a guarantee that warming finished or improved latency. Apple recommends useful lead time and stable instruction/tool prefixes. Use repeated baseline runs to assess changes; the app does not infer a performance improvement from one sample.

The SDK tokenizer currently rejects prompts or transcript history that contain image attachments, even when the same model can generate from those images. For image runs, the app therefore estimates admission from the countable text, instructions, tools, schemas, and attachment-stripped history, then lets the Foundation Models session enforce the real image-inclusive context limit during generation. Run details explicitly report **image input token count unavailable**; the estimate never assigns a made-up token cost to an image. Text-only runs continue to use the complete SDK token count.

Output and custom-tool schemas support strings, integers, `Double` numbers, Booleans, string choices, objects, arrays, nulls, unions, reusable references, and image references. Object properties can be optional, and object schemas can choose whether missing optional properties appear as explicit null values. String patterns, numeric bounds, and array counts map to the SDK generation guides; one-value choices, paired numeric bounds, equal array bounds, and nested item constraints cover constant, range, exact-count, and element-guide behavior. Schemas are bounded by depth and node limits and are saved with the suite. Scoring operates on final serialized JSON using the selected text metrics, field assertions, or AI rubric.

## SDK 27 inventory and boundaries

Research used Xcode MCP documentation and the installed Xcode 27 beta 6 SDK on 2026-09-05. Availability and context size are read from the running model; this Mac reported AFM 3 Core Advanced with an 8,192-token context during verification.

| Apple API or feature | App behavior |
|---|---|
| Dynamic instructions and profiles (27) | New two-stage tool workflow, per-session state and lifecycle evidence. |
| Custom tools and runtime schemas | Fixture/HTTP tools and guided output use recursive schemas, constraints, reusable definitions, explicit-null objects, and image-reference arguments. The base APIs predate 27. |
| Streaming, usage and prewarming | New selectable execution paths, first-content timing, existing cached/input/output/reasoning usage. Base streaming/prewarm predate 27. |
| Multimodal image prompting (27) | Image attachments, labels and capability admission are integrated; custom tool schemas can receive image references resolved from the session transcript. The public tokenizer cannot count image-bearing input, so image token cost is reported as unavailable and final context admission remains with the framework. |
| Model capabilities, identity and context (27) | Recorded per run and used for admission. Variant is observable, not publicly selectable. |
| Reasoning and ContextOptions (27) | Existing reasoning controls/traces; only capabilities actually supported by the model are usable. |
| Private Cloud Compute (27) | Existing dormant implementation stays unavailable in the public app because it requires managed entitlement. Quota UI is not presented as working without that entitlement. |
| Persistent/mutable transcripts and history transforms | Each sample can restore a transcript and run setup turns before its scored prompt. Keep, reset, and recent-turn policies control durable history and model-facing projection. |
| Core AI and custom LanguageModel providers (27) | Integrated provider selection, local resource loading, capability admission, and HTTP event adapter. Real model resources or an inference service are required. The tiny Core AI fixture verifies loading/generation, not answer quality. |
| Feedback attachments | Opt-in captured transcripts can be reviewed and exported as JSON or Apple feedback attachments with sentiment, issue categories, explanations, and desired output. Export does not upload feedback. |
| SystemLanguageModel.Adapter | Obsoleted in SDK 27; do not add an adapter picker. |

Sources:

- [Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)
- [Tool](https://developer.apple.com/documentation/foundationmodels/tool)
- [DynamicGenerationSchema](https://developer.apple.com/documentation/foundationmodels/dynamicgenerationschema)
- [ToolCallingMode](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct)
- [Optimizing key-value caching](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions)
- [Multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)

See [validated judge evidence and trace coverage](judge-validation.md) for how rubric contradictions are handled and what complete public transcripts can expose.
