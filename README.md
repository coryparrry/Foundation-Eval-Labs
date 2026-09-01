# Foundation Evals

A small native macOS app for running repeatable evaluations against Apple's on-device and Private Cloud Compute Foundation Models without working in Xcode.

## Run it

Requirements:

- macOS 27 on an Apple Intelligence-eligible Mac
- Apple Intelligence enabled and the system model downloaded
- Xcode 27 command-line tools for local development builds

Private Cloud Compute additionally requires network access, available quota, and Apple's managed entitlement on an approved signing identity.

From this repository:

```sh
./script/build_and_run.sh
```

That creates `dist/Foundation Evals.app`. Quit the app before rebuilding; the script will never terminate an evaluation that is already running. After the first build, open the `.app` directly for normal use without opening Xcode.

For an approved Private Cloud Compute development setup, build and launch the entitled Release configuration:

```sh
FOUNDATION_EVALS_TEAM_ID=ABCDE12345 ./script/build_and_run.sh --pcc
```

Replace the placeholder with the Apple Developer team approved for the managed entitlement. The script defaults to an `Apple Development` identity; set `FOUNDATION_EVALS_SIGNING_IDENTITY` when an approved distribution identity is required. It allows Xcode to update provisioning, then verifies the exact team identifier and embedded entitlement before installing or launching the app.

The normal Debug build deliberately has no cloud entitlement. The app requires both the managed entitlement and a non-ad-hoc team signature before enabling cloud requests.

The app itself uses the system `FoundationModels` framework. It does not link the Xcode-only `Evaluations` developer framework, so a built app has no evaluation-runtime dependency on Xcode.

## What it does

- Gives every case a fresh `LanguageModelSession` with shared instructions.
- Controls provider, reasoning level, sampling, temperature, seed, response headroom, input policy, and reference delivery per suite.
- Supports a bounded read-only reference-search tool; saved traces keep call metadata while omitting queries and returned passages.
- Runs one to five repetitions to reveal probabilistic variation.
- Supports deterministic exact/contains checks, trace collection without scoring, and a guided 1–4 AI rubric with editable templates.
- Shows selected-provider readiness, capabilities, quota state, and the complete request workload before a run starts.
- Imports or accepts dropped UTF-8 text, JSON, CSV, extractable PDF text, and up to four image attachments.
- Records the effective model input, response, score, rationale, separate subject/judge latency and public token usage, framework error categories, OS/locale, prompt version, and attachment hashes.
- Saves searchable run history locally in Application Support, supports confirmed local deletion, and exports complete JSON reports.
- Filters and searches run results, keeps failures expanded for review, and provides one-click response copying.
- Emits metadata-only `OSSignposter` intervals for Instruments correlation.

## Evaluation practice

Use deterministic checks whenever correctness is computable. Use a model judge only for subjective qualities, write concrete rating criteria, and calibrate it against a small human-reviewed sample before making it a release gate. Keep representative ordinary, boundary, malformed, safety, and adversarial cases in the suite, and version prompts whenever instructions, context preparation, or validation changes.

For the AI rubric, enter one observable requirement per line and keep the set to four or fewer. The app applies a fixed scale: 4 means every requirement is fully met, 3 means the core requirements are met with only minor issues, 2 means a material requirement failed, and 1 means the response is fundamentally wrong or off-task. Scores 3–4 pass. Add a verified reference answer for factual tasks; leave it blank only when multiple open-ended answers can be valid.

Apple's current evaluation model is dataset → subject → evaluators → aggregate results. The app follows that shape while presenting it as an interactive macOS workflow. See [Evaluating language model responses](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses) and [Designing specific, measurable criteria](https://developer.apple.com/documentation/evaluations/designing-evaluation-criteria).

## Files and traces

Foundation Models exposes native attachments for images, not arbitrary document files. The app extracts text from supported text/PDF files and clearly delimits it in the prompt; images use `Attachment(imageURL:)` with stable labels.

The JSON trace is app-owned because Foundation Models does not expose a programmatic export of its Instruments track. For deeper local profiling, use Apple's Foundation Models Instruments template, which shows sessions, requests, instructions, inference, tools, loading, timing, and token details. Instruments recordings can contain unencrypted prompts and responses, so treat them as sensitive. See [Analyzing runtime performance](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app).
