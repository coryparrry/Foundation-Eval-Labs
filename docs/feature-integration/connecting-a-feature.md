# Connecting a feature

Supported today: macOS 27, Xcode 27, the public `FoundationEvalsIntegration` and `FoundationEvalsAppleBridge` products, and the Connected Feature example.

This is not a general iPhone or CI worker. Manual Xcode runs still work if the in-app launcher cannot reach the selected paths.

## 1. Add the package

In your app or test target, add the local package at `Packages/FoundationEvalsIntegration`. Import `FoundationEvalsIntegration`. Import `FoundationEvalsAppleBridge` only where you decode Apple evaluation-result or transcript JSON.

Keep expected answers off the production input type. The feature should implement `FeatureUnderTest`.

## 2. Run the example

```sh
xcodebuild \
  -project Examples/ConnectedFeature/ConnectedFeature.xcodeproj \
  -scheme ConnectedFeature \
  -destination 'platform=macOS' \
  test
```

The app screen and `ReceiptCaptureTests` both call `ReceiptExtractor`. The discounted receipt currently returns `1000` pence because the parser reads `Subtotal` instead of `Total paid`. That is an example-only production bug.

Capture folders are published next to the test output, or under `Examples/ConnectedFeature/.foundation-evals/jobs/` when Foundation Evals writes `request.json`.

## 3. Import in Foundation Evals

1. Open the project overview.
2. Choose **Import Evidence…**.
3. Select a `.fevalrun` folder, an Apple evaluation-result JSON file, or a transcript JSON file.
4. Confirm the destination project shown in the preview.

Imported evidence is inspection-only. It does not approve a baseline or pass a release check.

## 4. Rerun the example

Authorize the Connected Feature `.xcodeproj` from an imported capture. Rerun uses the frozen case inputs, a new run ID, and the same importer. The old capture stays on disk.

## Troubleshooting

- `unable to resolve module Evaluations`: link Xcode’s MacOSX developer-library copy of `Evaluations.framework`. Do not vendor it.
- Live model unavailable: the native tests report unavailability. That is not a fake pass.
- Launcher missing capture: a zero exit with no `.fevalrun` is a failed capture.
- Stopping…: cancellation is not confirmed until the test process actually exits.
