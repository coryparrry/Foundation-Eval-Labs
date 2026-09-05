# Foundation Evals

A native macOS app for running repeatable evaluations, inspecting execution traces, and comparing saved runs against Apple's on-device Foundation Model without working in Xcode.

## Run it

Requirements:

- macOS 27 on an Apple Intelligence-eligible Mac
- Apple Intelligence enabled and the system model downloaded
- Xcode 27 command-line tools for local development builds

From this repository:

```sh
./script/build_and_run.sh
```

That creates `dist/Foundation Evals.app`. Quit the app before rebuilding; the script will never terminate an evaluation that is already running. After the first build, open the `.app` directly for normal use without opening Xcode.

The app itself uses the system `FoundationModels` framework. It does not link the Xcode-only `Evaluations` developer framework, so a built app has no evaluation-runtime dependency on Xcode.

## Development and tests

Open `FoundationEvals/FoundationEvals.xcodeproj` in Xcode, or run the unit tests from the repository root:

```sh
xcodebuild -project FoundationEvals/FoundationEvals.xcodeproj \
  -scheme FoundationEvals -destination 'platform=macOS' \
  -only-testing:FoundationEvalsTests test
```

Omit `-only-testing:FoundationEvalsTests` to include the UI tests. Tests that exercise real inference require a ready model; UI tests require an interactive Mac with the necessary automation permissions.

The build script creates a local Debug app. It does not produce a notarized release. See [release readiness](docs/release-readiness.md) for the remaining distribution work.

## Providers and privacy

The default provider is Apple's on-device Foundation Model. The app also supports a selected local Core AI resource folder and a developer-owned HTTP provider on literal `127.0.0.1`. Core AI resources are supplied separately; see [Core AI integration](docs/coreai-provider.md). The [custom provider protocol](docs/custom-provider-protocol.md) describes the request and response format.

Private Cloud Compute is also available when the app has an approved entitlement and the system reports availability; those requests use Apple's network service and quota.

Custom HTTP providers receive evaluation request content, and configured HTTP tools receive their call arguments. These connections are restricted to loopback, but the separate local service controls what it does with that data, including any onward network requests. Only use services you trust. Optional Spotlight tools can expose matching local file content to the selected model.

Suites, drafts, run records, and imported attachments are stored under `~/Library/Application Support/FoundationEvals/`. Saved JSON and exports can contain prompts, responses, extracted reference text, tool arguments and outputs, and selected resource bookmarks. The app does not encrypt these files itself. Treat exported reports and shared traces as potentially sensitive.

The MCP connector described below permits local clients to read and change evaluation data without a bearer credential. Host and origin checks do not make it an authenticated service. Connecting to Codex also updates `~/.codex/config.toml`.

## Agent control with MCP

Open the app's **Settings**, choose **Connect to Codex**, then restart Codex. The app writes a managed entry directly to `~/.codex/config.toml`. Keep Foundation Evals running while an agent uses the connector.

The local, unauthenticated loopback endpoint uses standard MCP `2025-06-18`, with host and origin checks. Agents can replace the ordered suite, upload and remove bounded references, start/poll/cancel runs, list or delete saved runs, and read attachment or canonical run resources. Agents can also call `eval_analyze_run` with a saved `runID` and optional `baselineRunID` to inspect coverage, repeatability, performance, and compatible case comparisons without another model request. The port is fixed at `17873`; a conflict stops the connector and is shown in Settings instead of changing the installed URL.

## What it does

- Gives every case a fresh `LanguageModelSession` with shared instructions.
- Controls sampling, temperature, seed, response headroom, input policy, and reference delivery per suite.
- Supports a bounded read-only reference-search tool; saved traces keep call metadata while omitting queries and returned passages.
- Runs one to five repetitions to reveal probabilistic variation.
- Supports deterministic exact/contains checks, trace collection without scoring, and a guided 1–4 AI rubric with editable templates.
- Shows on-device model readiness, capabilities, and the complete request workload before a run starts.
- Imports or accepts dropped UTF-8 text, JSON, CSV, extractable PDF text, and up to four image attachments.
- Records the effective model input, response, available readable reasoning, score, rationale, separate subject/judge latency and public token usage, framework error categories, OS/locale, prompt version, and attachment hashes.
- Saves searchable run history locally in Application Support, supports confirmed local deletion, and exports complete JSON reports.
- Filters run results in a compact list, shows one selected result at a time, and provides one-click response copying.
- Emits metadata-only `OSSignposter` intervals for Instruments correlation.

## Comparing and investigating runs

Open a saved run to inspect coverage, per-case repeatability, and subject/judge usage. Choose a saved baseline to compare matching cases under the same scoring contract. Changed cases, missing samples, and incompatible scoring are reported explicitly. Observed differences are descriptive; a small number of repetitions does not establish statistical significance.

New samples include measured preparation, generation, and scoring stages plus reference-tool durations. Older runs remain readable and show unavailable timing where it was not recorded.

See [evaluation design and research](docs/evaluation-design.md) for the rationale and remaining opportunities.

## Evaluation practice

Use deterministic checks whenever correctness is computable. Use a model judge only for subjective qualities, write concrete rating criteria, and calibrate it against a small human-reviewed sample before making it a release gate. Keep representative ordinary, boundary, malformed, safety, and adversarial cases in the suite, and version prompts whenever instructions, context preparation, or validation changes.

For the AI rubric, enter one observable requirement per line and keep the set to four or fewer. The scale is: 4 means every requirement is fully met, 3 means only minor issues remain, 2 means a material requirement failed, and 1 means the response fundamentally failed. Scores 3–4 pass. Add a verified reference answer for factual tasks; the model judge compares meaning, so the reference is not a required literal response. For deterministic whole-response equality, put `exact: "REQUIRED TEXT"` on its own rubric line. Recognized standalone exact rules run in application code; the remaining requirements receive separate required score/rationale fields from the model. Compound or unrecognized literal requirements remain model-scored. Invalid assessments receive at most one fresh-session repair and are never counted as passes without validation.

Apple's current evaluation model is dataset → subject → evaluators → aggregate results. The app follows that shape while presenting it as an interactive macOS workflow. See [Evaluating language model responses](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses) and [Designing specific, measurable criteria](https://developer.apple.com/documentation/evaluations/designing-evaluation-criteria).

## Files and traces

Foundation Models exposes native attachments for images, not arbitrary document files. The app extracts text from supported text/PDF files and clearly delimits it in the prompt; images use `Attachment(imageURL:)` with stable labels.

The JSON trace is app-owned because Foundation Models does not expose a programmatic export of its Instruments track. For deeper local profiling, use Apple's Foundation Models Instruments template, which shows sessions, requests, instructions, inference, tools, loading, timing, and token details. Instruments recordings can contain unencrypted prompts and responses, so treat them as sensitive. See [Analyzing runtime performance](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app).

## License and project notes

Foundation Evals is available under the [MIT License](LICENSE). Dependencies retain their own terms; [third-party notices](FoundationEvals/FoundationEvals/Resources/THIRD_PARTY_NOTICES.txt) reproduce license and notice files from the pinned package revisions. User-supplied model resources are separate from this source license.

`worklog.md` records historical development sessions, including superseded implementations and earlier validation limits. It is not the current product contract or release certification.
