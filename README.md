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

For the AI rubric, enter one observable requirement per line and keep the set to four or fewer. The scale is: 4 means every requirement is fully met, 3 means only minor issues remain, 2 means a material requirement failed, and 1 means the response fundamentally failed. Scores 3–4 pass. Add a verified reference answer for factual tasks; an exact candidate/reference match passes deterministically without asking the model judge.

Apple's current evaluation model is dataset → subject → evaluators → aggregate results. The app follows that shape while presenting it as an interactive macOS workflow. See [Evaluating language model responses](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses) and [Designing specific, measurable criteria](https://developer.apple.com/documentation/evaluations/designing-evaluation-criteria).

## Files and traces

Foundation Models exposes native attachments for images, not arbitrary document files. The app extracts text from supported text/PDF files and clearly delimits it in the prompt; images use `Attachment(imageURL:)` with stable labels.

The JSON trace is app-owned because Foundation Models does not expose a programmatic export of its Instruments track. For deeper local profiling, use Apple's Foundation Models Instruments template, which shows sessions, requests, instructions, inference, tools, loading, timing, and token details. Instruments recordings can contain unencrypted prompts and responses, so treat them as sensitive. See [Analyzing runtime performance](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app).
