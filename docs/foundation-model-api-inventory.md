# Foundation Models SDK 27 API inventory

This is the implementation inventory for Foundation Evals against the public macOS 27 SDK in Xcode 27 beta 6. It groups overload families by behavior, but records every public customization surface that changes model selection, session behavior, generation, context, tools, multimodal input, transcript state, feedback, or provider execution.

The primary source is the shipped Swift interface at:

```text
/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/FoundationModels.framework/Versions/A/Modules/FoundationModels.swiftmodule/arm64e-apple-macos.swiftinterface
```

Line references below refer to that interface unless an overlay is named. Apple documentation links are included where the behavior cannot be inferred safely from a declaration alone.

## Status vocabulary

| Status | Meaning for Foundation Evals |
|---|---|
| Integrated | The app has a real execution or inspection path now. |
| Adapter ready | Code exists behind an explicit custom-provider selection; a real inference process is still supplied by the user. |
| Implementable | The SDK surface is public and usable in this macOS target, but the app does not expose it yet. |
| Blocked | Public API exists, but an entitlement, exported model resource, or user-owned service is required. |
| Unavailable | The API cannot run in the relevant environment or platform. |
| Obsolete | The SDK 27 interface removes or renames the old surface; do not add new UI for it. |

## Capability and implementation matrix

| Capability or customization | Public SDK 27 surface | Foundation Evals status | Boundary |
|---|---|---|---|
| On-device system model | `SystemLanguageModel.default`, `init(useCase:guardrails:)`, availability, supported languages, locale support, token counting, context size, variant | Integrated | Availability is runtime state; the public variant is observable, not selectable. |
| System use case | `.general`, `.contentTagging` | Integrated | A use case selects Apple's system specialization; it is separate from sampling and prompts. |
| Guardrails | `.default`, `.permissiveContentTransformations` | Integrated | Permissive applies to text transformation requests and does not guarantee the model will answer. Guided output continues to use default guardrails. |
| Private Cloud Compute | `PrivateCloudComputeLanguageModel`, async context/language queries, availability, quota state and errors | Present but blocked | Requires Apple's managed entitlement. Availability and quota are separate admission checks. |
| Custom providers | `LanguageModel`, `LanguageModelExecutor`, generation request and channel events | Adapter ready | The local HTTP adapter is disabled until explicitly selected. It accepts only literal loopback endpoints. A user-owned inference process is still required. |
| Core AI exported models | `CoreAILanguageModel(resourcesAt:)` from Apple's `CoreAILanguageModels` package | Integrated | Requires an external Core AI export resource. The native acceptance run loaded and generated with Apple's tiny random-weight test model; this proves the runtime path, not answer quality or arbitrary model compatibility. Model resources are not included in this repository. |
| Capability admission | `LanguageModelCapabilities` with `.vision`, `.guidedGeneration`, `.reasoning`, `.toolCalling` | Integrated for Apple models; configurable for custom HTTP | A custom provider must advertise only behavior its executor implements. |
| Instructions | Static `Instructions`, result builder, dynamic instructions | Integrated | Instructions must contain trusted app-authored policy. User/file/network content belongs in `Prompt`. |
| Dynamic profiles | `DynamicProfile`, modifiers for model/options/history/error policy, lifecycle callbacks, `SessionProperty` | Integrated in a bounded tool workflow | A profile has one active branch. Tool calls already issued before a transition may still complete. |
| Text response | `respond` and `streamResponse` overloads for `String`, `Prompt`, and builders | Integrated | Streaming snapshots are aggregate partial values. |
| Guided generation | `@Generable`, `GeneratedContent`, typed and runtime `GenerationSchema` overloads | Integrated for bounded runtime schemas | The editor covers nested objects, arrays, string choices, unions, references, null, image references, explicit-null object representation, string patterns, numeric bounds, and array counts. Single choices, paired bounds, equal counts, and constrained item schemas provide the constant, range, exact-count, and element-guide behavior for the exposed types. The number field uses `Double`; separate `Float` and `Decimal` field types are not exposed. |
| Generation options | sampling, temperature, maximum response tokens, tool calling mode | Integrated | Unsupported options must be rejected against the selected model's capabilities. |
| Context options | schema-in-prompt policy and reasoning level | Integrated | `includeSchemaInPrompt` is tri-state. `nil` preserves framework behavior. |
| Request metadata | `[String: any ConvertibleToGeneratedContent]` on response APIs | Integrated | Metadata is included in transcripts and passed through custom executor requests. |
| Usage | input total/cached and output total/reasoning counts plus metadata | Integrated | Usage is cumulative for a response; absence must stay unavailable rather than become zero. |
| Prewarming | `prewarm(promptPrefix:)` | Integrated | A hint only. Apple recommends at least about one second of useful lead time and stable instruction/tool prefixes. |
| Tools | `Tool`, generated/runtime argument schemas, async calls, schema-in-instructions switch | Integrated for fixture and literal-loopback HTTP tools | Scalar primitives cannot be used directly as `Arguments`; use a `@Generable` or `GeneratedContent` structure. |
| Tool call policy | `.allowed`, `.required`, `.disallowed` | Integrated | Required mode needs an exit path after useful tool output. |
| Image prompt attachments | `Attachment` from `CGImage`, `CIImage`, `CVPixelBuffer`, image URL, and AppKit `NSImage` | Integrated | Requires `.vision`; file admission and token cost still apply. |
| Image-reference tool arguments | `ImageReference: Generable`, `resolved(in:)` | Integrated | Custom-tool schemas can declare image references. At call time, the app resolves each label only against the active session history and sends the configured loopback endpoint bounded identity and image metadata, without file paths, URLs, or image bytes. |
| Vision tools | `OCRTool`, `BarcodeReaderTool` | Integrated | Suites can independently enable Apple's native OCR and barcode tools. They share the per-sample tool-call budget and enforce the tool-output token reserve; Apple documents both tools as unavailable in Simulator. |
| Mutable transcript | mutable/range-replaceable `Transcript`, Codable persistence | Integrated | Saved transcripts can be restored into a run, setup turns append to the same session, and the resulting transcript can be captured for inspection and export. Do not mutate a session transcript while it is responding. |
| History view | mutable `Transcript.HistoryView`, `session.history` | Integrated | Suites can keep all history, reset it, or retain a bounded number of complete turns before the scored prompt. The view excludes leading instructions. |
| History transforms | `.historyTransform(([Transcript.Entry]) -> [Transcript.Entry])` profile modifier | Integrated | Per-case keep/reset/recent-complete-turn projection preserves the active prompt and tool continuation while leaving the stored transcript intact. |
| Feedback export | three `logFeedbackAttachment` overloads returning `Data` | Integrated | Saved runs expose transcript review, JSON export, and user-authored Apple feedback attachment export. The app rehydrates the recorded provider and never uploads the attachment implicitly. |
| Refusal explanation | `LanguageModelError.refusal`, async explanation and stream | Integrated | On refusal, the app keeps the original error and makes one bounded best-effort explanation request. Explanation failure or timeout is recorded and shown separately. |
| Spotlight search tool | `_CoreSpotlight_FoundationModels.SpotlightSearchTool` and configurable pipeline | Integrated | Default-off file and Core Spotlight sources, explicit folder scope, bounded results/attributes/output, all guide modes, result formatting, a manual identity resolver, one concrete custom stage, and aggregate-only trace metadata are available. The app never reads Contacts for identity resolution. |
| Platform availability | Framework broadly includes watchOS 27; system model remains unavailable on watchOS; tvOS unavailable | macOS target supported | Foundation Evals is a macOS 27 app. |

## Exact session and generation surfaces

The SDK 27 generic session initializers accept every `LanguageModel`, which is what makes both PCC and custom providers first-class rather than parallel response clients (lines 1911–1961):

```swift
convenience init(
    model: some LanguageModel,
    tools: [any Tool] = [],
    transcript: Transcript
)

convenience init(
    model: some LanguageModel,
    tools: [any Tool] = [],
    instructions: Instructions? = nil
)

convenience init(
    model: some LanguageModel,
    tools: [any Tool] = [],
    instructions: String? = nil
)

func prewarm(promptPrefix: Prompt? = nil)
```

Response APIs come in synchronous-result and streaming families for plain `String`, `Prompt`, and `@PromptBuilder` input. Each family has plain text, runtime schema, and generic `Generable` output overloads. All accept:

```swift
options: GenerationOptions = GenerationOptions()
contextOptions: ContextOptions = ContextOptions(/* schema overload defaults true */)
metadata: [String: any ConvertibleToGeneratedContent] = [:]
```

The runtime-schema overload returns `GeneratedContent`; the generic overload returns the requested `Generable`. Streaming returns `ResponseStream<Content>` and `collect()` produces the final response. The declarations occupy lines 2058–2181.

`GenerationOptions` exposes (lines 3200–3313):

```swift
var samplingMode: SamplingMode?       // .greedy, .random(top:seed:),
                                      // .random(probabilityThreshold:seed:)
var temperature: Double?
var maximumResponseTokens: Int?
var toolCallingMode: ToolCallingMode? // .allowed, .required, .disallowed
```

`ContextOptions` is exactly (lines 3132–3147):

```swift
struct ContextOptions: Sendable, Equatable {
    var includeSchemaInPrompt: Bool?
    var reasoningLevel: ReasoningLevel?

    init(
        includeSchemaInPrompt: Bool? = nil,
        reasoningLevel: ReasoningLevel? = nil
    )

    enum ReasoningLevel: Sendable, Equatable {
        case light
        case moderate
        case deep
        case custom(String)
    }
}
```

Schema-in-prompt inclusion normally defaults to `true` for guided generation. Setting it to `false` is appropriate for a provider trained on the schema or when exhaustive examples already establish the format. Admission must check the actual selected model's `.guidedGeneration` and `.reasoning` capabilities.

## Schema and generated-content vocabulary

The app's bounded runtime schema editor maps the SDK vocabulary as follows:

- `GeneratedContent.Kind`: null, Boolean, number, string, array, and ordered structure.
- `DynamicGenerationSchema.null` and object schemas with `representNilExplicitlyInGeneratedContent`.
- Objects with named, described, optional properties.
- `anyOf` for nested schemas or allowed string values.
- Arrays with minimum and maximum element counts.
- Named schema references and dependent schemas through `GenerationSchema` construction.
- String guides: constant, `anyOf`, and regex pattern.
- Numeric minimum, maximum, and closed ranges.
- Array minimum, maximum, exact/ranged count, and element guides.
- Codable `GenerationSchema`, enabling it to cross the custom-provider protocol boundary.

The main declarations are lines 1336–1460 and 3151–3412. Foundation Evals exposes this vocabulary through a bounded recursive editor with depth and node limits, validation, persistence, and MCP round-tripping. Choice fields map to string `anyOf`; a single choice has the same constraint as `constant`. Separate or paired numeric bounds map to minimum, maximum, or closed ranges. Array bounds map to minimum, maximum, ranged, or exact count, and the nested item schema carries element constraints. Object schemas can include missing optional properties as explicit null values. The app's number field uses `Double`; separate `Float` and `Decimal` schema types are not exposed.

String-pattern validation proves that the text is a valid Swift `Regex`; it does not prove that a selected model provider's constrained decoder supports every regex feature. Providers report unsupported patterns at request time through `LanguageModelError.unsupportedGenerationGuide`. Foundation Evals preserves that error's `schemaName` and `debugDescription` for diagnosis without persisting its unrestricted metadata dictionary.

## Tools and image references

The tool contract is (lines 3054–3127):

```swift
protocol Tool<Arguments, Output>: Sendable {
    associatedtype Arguments: ConvertibleFromGeneratedContent
    associatedtype Output: PromptRepresentable

    var name: String { get }
    var description: String { get }
    var parameters: GenerationSchema { get }
    var includesSchemaInInstructions: Bool { get }

    @concurrent
    func call(arguments: Arguments) async throws -> Output
}
```

SDK 27 image-reference arguments are exact (lines 3019–3050):

```swift
struct ImageReference: Sendable, Equatable, Generable {
    let attachmentLabel: String
    func resolved(
        in transcript: some Sequence<Transcript.Entry>
    ) -> Transcript.ImageAttachment?
}
```

This allows a generated tool argument to refer to an image already attached to the session. Foundation Evals exposes the type in custom-tool schemas and resolves it from the active session history during each call. The loopback HTTP payload receives only the declared attachment label, dimensions, orientation, and reference kind. It does not receive the attachment URL, local path, or image bytes. A missing label is rejected instead of triggering an arbitrary file lookup.

The `_Vision_FoundationModels` overlay adds:

```swift
OCRTool(name: String? = nil, description: String? = nil)
BarcodeReaderTool(name: String? = nil, description: String? = nil)
```

They are real `Tool` conformers. Foundation Evals exposes separate OCR and barcode toggles and registers the selected native tool instance directly so Foundation Models can bind its session history and resolve `ImageReference` values. Dynamic-profile tool-call and tool-output hooks enforce the shared per-sample call limit and output-token limit without hiding that native instance behind a forwarding wrapper. Transcript calls and outputs are captured when transcript capture is enabled. The declarations are lines 12–83 of `_Vision_FoundationModels.swiftinterface`. OCR is unavailable on watchOS; barcode reading includes watchOS 27. Apple's documentation states the tools are unavailable in Simulator.

The base framework accepts image attachments from `CGImage`, `CIImage`, `CVPixelBuffer`, or an image URL. `_FoundationModels_AppKit` adds `Attachment.init(_ nsImage: NSImage, orientation:)` at overlay lines 11–14.

## Mutable transcript, history, and dynamic profiles

The complete transcript is Codable and becomes mutable in SDK 27 (lines 2235–2729):

```swift
struct Transcript: Sendable, Equatable, RandomAccessCollection,
                   MutableCollection, RangeReplaceableCollection, Codable

var LanguageModelSession.transcript: Transcript { get set }
```

It can be supplied to `LanguageModelSession(model:tools:transcript:)` for exact rehydration. A restored transcript includes its leading instructions and tool definitions. Mutating it changes persistent session state and invalidates relevant key-value cache reuse. The framework rejects mutation while a response is active and rejects concurrent responses on one session.

The instruction-free view is exact (lines 2664–2700 and 1071–1075):

```swift
struct Transcript.HistoryView: MutableCollection,
                               RandomAccessCollection,
                               RangeReplaceableCollection,
                               Sendable

var Transcript.history: Transcript.HistoryView { get set }
var LanguageModelSession.history: Transcript.HistoryView { get set }
```

Dynamic sessions can start from either a profile or dynamic instructions (lines 802–1127):

```swift
LanguageModelSession(profile: some DynamicProfile,
                     history: some Collection<Transcript.Entry> = [])

LanguageModelSession(model: some LanguageModel = SystemLanguageModel.default,
                     dynamicInstructions: some DynamicInstructions,
                     history: some Collection<Transcript.Entry> = [])
```

A profile can modify model, temperature, sampling, maximum response tokens, reasoning, tool calling, transcript error handling, and the history projection. It also provides `onPrompt`, `onResponse`, `onReasoning`, `onToolCall`, `onToolOutput`, `onActivate`, and `onDeactivate` callbacks. `@SessionProperty` reads and writes values stored in the session's `SessionPropertyValues`.

The history transform signature is (line 980):

```swift
func historyTransform(
    _ transform: @escaping ([Transcript.Entry]) -> [Transcript.Entry]
) -> some LanguageModelSession.DynamicProfile
```

This closure receives a value copy for the model-facing request. Use `session.history` or `session.transcript` when the product intends to mutate durable conversation state.

Foundation Evals restores saved transcript history, generates configured setup turns in the same session, and applies the selected history policy before the scored prompt. The saved conversation trace records restored and retained entry counts plus each setup and scored turn. This uses durable transcript mutation rather than the profile-only history transform.

## Feedback export

The three public overloads return JSON attachment data (lines 3470–3513):

```swift
func logFeedbackAttachment(
    sentiment: LanguageModelFeedback.Sentiment?,
    issues: [LanguageModelFeedback.Issue] = [],
    desiredOutput: Transcript.Entry? = nil
) -> Data

func logFeedbackAttachment(
    sentiment: LanguageModelFeedback.Sentiment?,
    issues: [LanguageModelFeedback.Issue] = [],
    desiredResponseText: String?
) -> Data

func logFeedbackAttachment(
    sentiment: LanguageModelFeedback.Sentiment?,
    issues: [LanguageModelFeedback.Issue] = [],
    desiredResponseContent: (any ConvertibleToGeneratedContent)?
) -> Data
```

Sentiment is positive or negative. Issue categories are `incorrect`, `unhelpful`, `tooVerbose`, `didNotFollowInstructions`, `stereotypeOrBias`, `suggestiveOrSexual`, `vulgarOrOffensive`, and `triggeredGuardrailUnexpectedly`; an issue can also carry a free-text explanation. The app must show the data and let the user choose where to save or send it.

Foundation Evals retains the recorded provider configuration with each run and rehydrates that provider only when the user requests a feedback attachment. The export form exposes the distinct desired-response text, generated-content JSON, and transcript-entry JSON overloads; both JSON editors validate their SDK representation and all desired-output editors enforce a 32,000-character limit. Core AI rehydration can therefore report a missing or stale model resource folder at export time. Transcript JSON remains separately reviewable and exportable even when feedback attachment creation is unavailable.

## Refusal explanations

`LanguageModelError.refusal` carries a `LanguageModelError.Refusal`. Its explanation surfaces are (lines 1678–1686):

```swift
var explanation: LanguageModelSession.Response<String> { get async throws }
var explanationStream: LanguageModelSession.ResponseStream<String> { get }
```

Foundation Evals uses the async result after catching a refusal. It preserves the refusal as the sample or judge error, bounds explanation generation to three seconds, stores at most 4,096 characters, and records timeout or explanation-generation failure separately. The result and conversation error views show the explanation or the secondary failure instead of replacing the refusal with it.

## Custom `LanguageModel` executor contract

The public protocols are exact (lines 1483–1519 and 1711–1907):

```swift
protocol LanguageModel: Sendable {
    associatedtype Executor: LanguageModelExecutor
        where Self == Executor.Model
    var capabilities: LanguageModelCapabilities { get }
    var executorConfiguration: Executor.Configuration { get }
}

protocol LanguageModelExecutor: Sendable {
    associatedtype Configuration: Hashable, Sendable
    associatedtype Model: LanguageModel

    init(configuration: Configuration) throws
    func prewarm(model: Model, transcript: Transcript)
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws
}
```

The request contains `id`, the full `transcript`, `enabledToolDefinitions`, optional guided `schema`, `generationOptions`, `contextOptions`, and generated-content `metadata`.

The channel accepts three event families:

- Response: append or replace text; add/remove attachments; update metadata; update cumulative usage.
- Reasoning: append or replace text; update a signature; update metadata; update cumulative usage.
- Tool calls: add/remove a call, append its argument JSON, update call or group metadata, and update cumulative usage.

Usage input contains total and cached token counts. Usage output contains total and reasoning token counts. The executor has to emit valid tool argument JSON incrementally and valid guided JSON through response text actions when a schema was requested.

### Foundation Evals loopback protocol

`EvaluationHTTPLanguageModel` implements that contract over one explicit HTTP POST. It never contacts the endpoint from initialization or `prewarm`. Configuration accepts only `http://127.0.0.1:<port>/...`, blocks credentials/query/fragment, disables redirects, proxies, cookies, credentials, and caches, and reserves the app's MCP port. The suite's optional custom configuration and `.customHTTP` provider selection keep it off for existing suites.

The request is JSON:

```json
{
  "protocolVersion": 1,
  "requestID": "UUID",
  "mode": "text | guided",
  "transcript": {},
  "enabledTools": [
    {"name": "lookup", "description": "...", "parameters": {}}
  ],
  "schema": null,
  "options": {
    "sampling": {"kind": "greedy | randomTopK | randomProbabilityThreshold"},
    "temperature": null,
    "maximumResponseTokens": 1024,
    "toolCallingMode": "allowed | required | disallowed"
  },
  "context": {
    "includeSchemaInPrompt": null,
    "reasoningLevel": "light | moderate | deep | custom:<value>"
  },
  "provider": {
    "contextSize": 8192,
    "capabilities": ["vision", "guidedGeneration", "reasoning", "toolCalling"]
  },
  "metadata": {}
}
```

The response is `application/x-ndjson`, one event per line. Supported events are:

```json
{"kind":"response","action":"append","entryID":"r1","segmentID":"s1","content":"Hello","tokenCount":1}
{"kind":"guidedResponse","action":"append","entryID":"r1","content":"{\"answer\":\"ok\"}","tokenCount":4}
{"kind":"reasoning","action":"append","entryID":"why1","content":"Check the input.","tokenCount":3}
{"kind":"reasoningSignature","entryID":"why1","signatureBase64":"yv4=","tokenCount":0}
{"kind":"toolCall","entryID":"calls1","callID":"call1","toolName":"lookup","content":"{\"query\":\"swift\"}","tokenCount":3}
{"kind":"usage","usageTarget":"response","usage":{"inputTokens":10,"cachedInputTokens":2,"outputTokens":5,"reasoningTokens":1}}
{"kind":"error","code":"backendError","message":"Explanation safe to show to the user."}
```

`action` defaults to `append`; response, guided-response, and reasoning events also support `replace`. Guided events are rejected for text requests and text response events are rejected for guided requests, so an inference backend cannot silently bypass the requested output contract. EOF completes the stream. At least one response or tool-call event is required.

Run the deterministic protocol fixture with:

```sh
python3 examples/custom_model_fixture_server.py
```

The fixture listens only on `127.0.0.1:19096`. It is deliberately not an inference backend: it does not interpret prompts or generate answers. Each route emits a fixed, bounded result for UI acceptance:

| Provider endpoint | Configure | Expected result |
|---|---|---|
| `http://127.0.0.1:19096/text` | No capabilities; timeout at least 10 seconds; enable streaming | Appends `Deterministic `, `fixture `, and `stream.` with 2 seconds between chunks. The final response is `Deterministic fixture stream.` |
| `http://127.0.0.1:19096/guided/simple` | Guided generation; output schema with one required string field named `answer` | `{"answer":"fixture"}` |
| `http://127.0.0.1:19096/guided/order` | Guided generation; use the nested order schema below | The documented nested A-104 order object |
| `http://127.0.0.1:19096/guided` | Guided generation | Selects the order object when the encoded schema contains `order`, `items`, `sku`, `quantity`, or `status`; otherwise selects the simple answer. This is a two-shape fixture, not a general schema generator. |
| `http://127.0.0.1:19096/reasoning` | Reasoning capability and a non-automatic reasoning level | Records deterministic reasoning, waits 2 seconds, then returns `Deterministic reasoning response.` |
| `http://127.0.0.1:19096/tool` | Tool-calling capability and the `lookupOrder` tool below | First request calls the real configured tool with `{"orderID":"A-104"}`. After its output appears in the next transcript, the provider returns `Tool result received. Order A-104 is shipped.` |
| `http://127.0.0.1:19096/malformed` | No capabilities | Sends malformed NDJSON and must surface an invalid-event failure. |
| `http://127.0.0.1:19096/error` | No capabilities | Sends the protocol error `fixtureBackendFailure`. |
| `http://127.0.0.1:19096/http-error` | No capabilities | Returns HTTP 503. |
| `http://127.0.0.1:19096/timeout` | Set the provider timeout to 1 second | Waits 5 seconds before sending headers, so the request must time out. |
| `http://127.0.0.1:19096/cancel` | Set the provider timeout to 30 seconds and enable streaming | Sends `Cancellation fixture started. `, pauses for 20 seconds, then finishes. Cancel during the pause to exercise cooperative cancellation and partial trace handling. |
| `http://127.0.0.1:19096/redirect` | No capabilities | Returns a 307 redirect to `/text`; the adapter refuses the redirect and reports the status. |
| `http://127.0.0.1:19096/generate` | Match capabilities to the feature under test | Automatically chooses guided, tool, reasoning, or text behavior. Explicit routes are preferable for acceptance evidence. |

For the nested guided route, configure this exact required output shape:

```json
{
  "order": {
    "id": "A-104",
    "status": "shipped",
    "items": [
      {"sku": "SKU-RED", "quantity": 2},
      {"sku": "SKU-BLUE", "quantity": 1}
    ]
  },
  "summary": "Order A-104 is shipped with 3 items."
}
```

In the schema editor, `order` is an object with required string fields `id` and `status`, plus a required `items` array of objects with required string `sku` and integer `quantity`; `summary` is a required root string.

For the tool route, add a tool named `lookupOrder` with one required string argument named `orderID`. Set its execution mode to **Local HTTP** and endpoint to `http://127.0.0.1:19096/tool/execute`. That endpoint returns `{"orderID":"A-104","status":"shipped","source":"deterministic-fixture"}`, proving the app executed the tool before the provider's second response. Use Review, exact-text, contains-text, or field assertions for these acceptance runs so an unrelated model-judge request does not introduce a second guided schema.

## Core AI feasibility

Apple's current Core AI route is an external Swift package, [apple/coreai-models](https://github.com/apple/coreai-models), with product `CoreAILM` and module `CoreAILanguageModels`. The integration shape is:

```swift
import CoreAILanguageModels
import FoundationModels

let modelURL = Bundle.main.url(
    forResource: "ExportedModel",
    withExtension: nil
)!
let model = try await CoreAILanguageModel(resourcesAt: modelURL)
let session = LanguageModelSession(model: model)
```

The project now references `CoreAILM`, but execution remains blocked until a compatible Core AI export is chosen and added as a bundled resource. The UI must keep that state visibly unavailable until the user supplies the resource and its redistribution constraints are known.

## Spotlight overlay

The `_CoreSpotlight_FoundationModels` overlay provides `SpotlightSearchTool` and a configurable search pipeline. Foundation Evals integrates the meaningful runtime-configurable surface as follows:

- **Sources:** File search requires one explicitly selected local folder, resolves symlinks, and rejects broad roots. Core Spotlight is a separate opt-in source. Each source has independent fetched attributes and result caps. The only public macOS source option is `.allowMail`, which remains a separate opt-in and requires Apple's Mail-search entitlement.
- **Guidance and output:** Complete, focused (all six content domains), and dynamic-profile guidance are configurable, as are structured/compact output and `maximumResponseSize`.
- **Contact resolution:** A default-off resolver maps only identity values entered into the suite to `ResolvedContact`. It does not query Contacts. The app exposes display name, alternate names, email addresses, and phone numbers; `nameComponents` is not inferred because parsing free-form names would add unrequested semantics rather than expose a reliable model customization.
- **Custom pipeline:** A default-off `CustomStage` removes duplicate item results by the wrapped `CSSearchableItem.uniqueIdentifier`. It accepts `.items`, produces `.items`, and only transforms the already bounded result set. `CustomStage` is executable Swift behavior, so arbitrary stages cannot be serialized safely from suite JSON; adding another transformation requires a concrete audited `Generable & CustomStage` implementation.
- **Tracing:** The async `searchResults` sequence feeds aggregate query, stage, status, and result-shape counts. Apple documents `.complete` as final for one query-stage pair, but does not document a terminal event for the whole sequence. Sample shutdown therefore waits for observed stages to complete and become briefly quiescent within a 250 ms bound, then cancels and joins the consumer before freezing the trace. Query text, contact values, identifiers, paths, file names, and result content are excluded from the Spotlight trace. Public transcript capture remains an explicit separate setting.

The overlay also accepts a `CSSearchableIndexDelegate`, but that delegate handles reindex requests for app-owned indexed data. Foundation Evals is a search client and has no app-owned indexing pipeline to rebuild, so exposing a no-op or user-selected delegate would be misleading. The central declarations occupy lines 15–505 of the Xcode 27 beta 6 macOS `_CoreSpotlight_FoundationModels.swiftinterface`; `CSSearchQuery.SourceOptions` is declared in `CSSearchQuery.h` and currently contains only the default value and `.allowMail` on macOS.

## Errors and deprecated surfaces

SDK 27 separates provider-independent `LanguageModelError` cases: context size exceeded, rate limited, guardrail violation, refusal, unsupported capability, unsupported transcript content, unsupported generation guide, unsupported language/locale, and timeout (lines 1527–1681). `SystemLanguageModel.Error.assetsUnavailable` and PCC network/quota/service errors remain provider-specific. `LanguageModelSession.Error` covers concurrent requests and transcript mutation constraints.

Do not build new code on these old names:

| Old API | SDK 27 state | Replacement |
|---|---|---|
| `SystemLanguageModel.Adapter`, `SystemLanguageModel(adapter:)` | Deprecated in 26.4 and obsoleted in 27 | `LanguageModel`/`LanguageModelExecutor`, or `CoreAILanguageModel` for Core AI exports. |
| `GenerationOptions.sampling` and `init(sampling:...)` | Deprecated/renamed | `samplingMode` and `init(samplingMode:...)`. |
| `Transcript.StructuredSegment.source` and `init(source:...)` | Deprecated/renamed | `schemaName` and `init(schemaName:...)`. |
| `LanguageModelSession.GenerationError` family | Deprecated in 27 | `LanguageModelError`, `SystemLanguageModel.Error`, `GeneratedContent.ParsingError`, and `LanguageModelSession.Error` as appropriate. |

## Primary Apple references

- [Foundation Models framework](https://developer.apple.com/documentation/foundationmodels)
- [Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)
- [Optimizing key-value caching in language model sessions](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions)
- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)
- [Tool](https://developer.apple.com/documentation/foundationmodels/tool)
- [DynamicGenerationSchema](https://developer.apple.com/documentation/foundationmodels/dynamicgenerationschema)
- [Core AI model integrations](https://github.com/apple/coreai-models)
