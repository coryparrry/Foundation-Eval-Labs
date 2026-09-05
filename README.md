# Foundation Evals

A native macOS app for testing Apple's Foundation Models. Build repeatable evaluation suites, inspect responses and execution traces, and compare results as you refine prompts, settings, and tools.

## Install

Requirements:

- macOS 27 or later
- A Mac that supports Apple Intelligence
- Apple Intelligence enabled and the on-device model downloaded

1. Download the latest notarized release of **Foundation Evals**.
2. Move **Foundation Evals.app** to your **Applications** folder.
3. Open the app and check that the model is ready.

Xcode is only needed to build from source.

## Run your first evaluation

1. Open **Suite Editor** and enter the instructions shared by your test cases.
2. Add cases with a prompt and, where appropriate, an expected response or reference answer. You can attach text, JSON, CSV, PDF, and image files as context.
3. Choose a scoring mode and set the number of repetitions.
4. Click **Run**. Select a result to inspect its response, score, explanation, timing, token usage, and tool activity.
5. Reopen runs from **Run History**, choose a saved baseline to compare results, or export a JSON report.

| Scoring mode | Use it for |
|---|---|
| **Exact text** | Matching the complete expected response, ignoring surrounding whitespace. |
| **Contains text** | Checking for required text, ignoring case and accents. |
| **AI rubric** | Assessing concrete requirements on a 1–4 scale; scores of 3 or 4 pass. |
| **Collect only** | Saving responses and traces without assigning a score. |

For AI rubrics, write one observable requirement per line and provide a verified reference answer for factual tasks. Inspect the judge's explanation alongside its score. Repetitions help reveal variation; a few runs do not establish statistical significance.

## Models and tools

The default provider is Apple's on-device Foundation Model. You can also load a compatible [Core AI model](docs/coreai-provider.md) or connect a [custom local HTTP provider](docs/custom-provider-protocol.md).

Use the **Features** page to configure custom tools, structured output, streaming, and tool workflows. The [tools and structured output guide](docs/foundation-model-features.md) includes a runnable local HTTP example.

## Connect an agent

Foundation Evals includes an MCP server so an agent can manage suites and references, run evaluations, inspect traces, and compare saved results.

To connect Codex:

1. Open **Settings** in Foundation Evals.
2. Choose **Connect to Codex**.
3. Restart Codex and keep Foundation Evals open.

The server provides an agent workflow guide during MCP initialization. Its HTTP endpoint is `http://127.0.0.1:17873/mcp` while the connector is running.

The connector listens only on this Mac and does not require credentials. Connected local clients can read and change evaluation data.

## Your data

Suites, imported attachments, and run history are saved in `~/Library/Application Support/FoundationEvals/`. The app does not encrypt these files itself. Saved traces and JSON exports can include prompts, responses, reference content, and tool arguments and outputs; review them before sharing.

On-device evaluations run locally. Custom HTTP providers and tools receive the content needed for their calls, and those separate services control any onward network use. Optional Private Cloud Compute uses Apple's network service when available. Spotlight tools can make matching local file content available to the selected model.

## Build from source

Use Xcode 27 with its command-line tools selected. From the repository root:

```sh
./script/build_and_run.sh
```

This creates and opens a development build at `dist/Foundation Evals.app`. Quit the app before rebuilding. You can also open `FoundationEvals/FoundationEvals.xcodeproj` directly in Xcode.

Run the tests with:

```sh
xcodebuild -project FoundationEvals/FoundationEvals.xcodeproj \
  -scheme FoundationEvals -configuration Debug \
  -destination 'platform=macOS' test
```

UI tests require an interactive Mac. The optional Core AI inference test requires compatible model resources.

## License

Foundation Evals is released under the [MIT License](LICENSE). Dependencies retain their own licenses; see [third-party notices](FoundationEvals/FoundationEvals/Resources/THIRD_PARTY_NOTICES.txt). Separately supplied model resources have their own terms.
