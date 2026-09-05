# Foundation Models experiments

The Features page configures real Foundation Models APIs. Configuration is saved with the suite and snapshotted in each run. Old suites open with these features disabled. MCP clients can supply `suite.features` to `eval_replace_suite`; omitting it preserves the existing configuration. `eval_get_state` returns the full declaration and limits; `eval_get_run` returns feature traces.

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

Endpoints must use literal `http://127.0.0.1:<port>/...`; the app's MCP port, credentials, query strings and fragments are rejected. Redirects, proxies, cookies and response caching are disabled. Requests are limited to 16 KiB and 256 argument tokens, responses to 4 KiB and 512 model tokens, and the request timeout is ten seconds. All custom tools share the selected 1–4 call allowance. Reference lookup has a separate allowance using the same setting. Custom arguments and outputs are saved locally in reports; avoid putting secrets in fixtures or responses.

## Performance and interpretation

**Streaming** consumes aggregate partial snapshots and records the time to the first nonempty response content. This is not an exact first-token measurement. Final response, token usage and transcript reasoning are collected from the completed stream. Structured and text streaming both work. Partial responses are not currently displayed live; the measurement appears in the completed sample trace.

**Prewarm** asks the framework to prepare the session before input token counting. It is a hint, not a guarantee that warming finished or improved latency. Apple recommends useful lead time and stable instruction/tool prefixes. Use repeated baseline runs to assess changes; the app does not infer a performance improvement from one sample.

Output fields currently support string, integer, number and Boolean types with optional fields. Scoring operates on the final serialized JSON using the existing text metrics or AI rubric. Nested schemas, field-specific assertions, arrays and enums are not yet exposed.

## SDK 27 inventory and boundaries

Research used Xcode MCP documentation and the installed Xcode 27 beta 6 SDK on 2026-09-05. Availability and context size are read from the running model; this Mac reported AFM 3 Core Advanced with an 8,192-token context during verification.

| Apple API or feature | App behavior |
|---|---|
| Dynamic instructions and profiles (27) | New two-stage tool workflow, per-session state and lifecycle evidence. |
| Custom tools and runtime schemas | New fixture/HTTP tools and guided output editor. The base APIs predate 27. |
| Streaming, usage and prewarming | New selectable execution paths, first-content timing, existing cached/input/output/reasoning usage. Base streaming/prewarm predate 27. |
| Multimodal image prompting (27) | Existing image attachments, labels, capability admission and token budgeting. Image-reference tool arguments are not exposed. |
| Model capabilities, identity and context (27) | Recorded per run and used for admission. Variant is observable, not publicly selectable. |
| Reasoning and ContextOptions (27) | Existing reasoning controls/traces; only capabilities actually supported by the model are usable. |
| Private Cloud Compute (27) | Existing dormant implementation stays unavailable in the public app because it requires managed entitlement. Quota UI is not presented as working without that entitlement. |
| Persistent/mutable transcripts and history transforms | Single fresh session per sample today; multi-turn scenarios remain a separate feature. |
| Core AI and custom LanguageModel providers (27) | Not integrated; require provider/model resources and their own capability/runtime validation. |
| Feedback attachments | Not exported yet; an explicit user review/export flow is needed. |
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
