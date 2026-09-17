# Connected Feature example

This macOS app and its tests call the same `ReceiptExtractor` production function. The capture tests write a version-1 `.fevalrun` bundle that Foundation Evals can import. They do not copy a prompt into the workbench and pretend that is the feature.

## What it demonstrates

The discounted receipt has paid total `GBP 7.50` (750 pence). The extractor currently reads `Subtotal` instead, so it returns `1000`. That bug is in the production parser. Captured bytes keep `1000`.

Three frozen cases:

- `receipt-ordinary-v1`
- `receipt-discounted-v1`
- `receipt-missing-date-v1`

## Run

Requires Xcode 27 and macOS 27. From the repository root:

```sh
xcodebuild \
  -project Examples/ConnectedFeature/ConnectedFeature.xcodeproj \
  -scheme ConnectedFeature \
  -destination 'platform=macOS' \
  -only-testing:ConnectedFeatureTests/ReceiptCaptureTests \
  test
```

The native Apple fixture lives in `ConnectedFeatureTests/NativeCompatibilityTests`. A live-model case reports unavailability instead of fabricating a pass.

## Launcher handoff

Foundation Evals may write `Examples/ConnectedFeature/.foundation-evals/request.json`. The capture test snapshots that file, validates the job directory, and publishes `<job-id>/<run-id>.fevalrun`. That directory is gitignored.
