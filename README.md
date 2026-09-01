# Foundation Evals

A small native macOS app for running repeatable evaluations against Apple's on-device Foundation Models without working in Xcode.

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

## What it does

- Gives every case a fresh `LanguageModelSession` with shared instructions.
- Runs one to five repetitions to reveal probabilistic variation.
- Supports deterministic exact/contains checks, human review, and an optional 1–4 model judge.
- Imports UTF-8 text, JSON, CSV, extractable PDF text, and up to four image attachments.
- Records the effective model input, response, score, rationale, separate subject/judge latency and public token usage, framework error categories, OS/locale, prompt version, and attachment hashes.
- Saves run history locally in Application Support and exports complete JSON reports.
- Emits metadata-only `OSSignposter` intervals for Instruments correlation.

## Evaluation practice

Use deterministic checks whenever correctness is computable. Use a model judge only for subjective qualities, write concrete rating criteria, and calibrate it against a small human-reviewed sample before making it a release gate. Keep representative ordinary, boundary, malformed, safety, and adversarial cases in the suite, and version prompts whenever instructions, context preparation, or validation changes.

Apple's current evaluation model is dataset → subject → evaluators → aggregate results. The app follows that shape while presenting it as an interactive macOS workflow. See [Evaluating language model responses](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses) and [Designing specific, measurable criteria](https://developer.apple.com/documentation/evaluations/designing-evaluation-criteria).

## Files and traces

Foundation Models exposes native attachments for images, not arbitrary document files. The app extracts text from supported text/PDF files and clearly delimits it in the prompt; images use `Attachment(imageURL:)` with stable labels.

The JSON trace is app-owned because Foundation Models does not expose a programmatic export of its Instruments track. For deeper local profiling, use Apple's Foundation Models Instruments template, which shows sessions, requests, instructions, inference, tools, loading, timing, and token details. Instruments recordings can contain unencrypted prompts and responses, so treat them as sensitive. See [Analyzing runtime performance](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app).
