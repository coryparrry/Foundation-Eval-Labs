# Feature 1 implementation note

Recorded against commit `bbbbcdae4d9ede98ef42c0238d79afa4300e91a4` (current `main` at the start of this work).

## Existing seams to reuse

| Role | Current file / function | Do not rebuild |
|---|---|---|
| In-process adapter (keeps `expected` on the input) | `Services/EvaluationFeatureAdapter.swift` — `EvaluationFeatureAdapter.evaluate`, `EvaluationFeatureAdapterRunner.run` | Do not copy `EvaluationFeatureInput.expected` into the public package API. Leave this runner working. |
| Persist a completed run | `Stores/EvaluationStore.swift` — `persistRun`, `runPreparedForHistory`, `loadRuns` | Imports save owned evidence through this history path, then stay inspection-only. |
| Bounded file read | `Stores/EvaluationAttachmentStorage.swift` — `readBoundedData`, `readImportFile` | Reuse the +1-byte streaming pattern. Add no-follow opening for evidence bundles. |
| SHA-256 of preserved bytes | `EvaluationStore.sha256` via CryptoKit | Package uses the same hex SHA-256 of actual bytes. |
| Atomic JSON write | `CanonicalJSON.data` + `write(options: .atomic)` | Bundle writer uses temp-file replacement in the working directory. |
| Release / completeness rules | `Services/EvaluationDevelopmentAnalysis.swift` — `EvaluationReleaseCheckEvaluator.report` | Imported evidence must not become a release pass. |
| Existing scoring | `Services/EvaluationFieldAssertions.swift`, `Services/MetricScorer.swift` | Do not add a second scoring engine. |
| Case-file import UI | `Views/CaseImportView.swift` + `SuiteEditorView` “Import Cases” | Separate from evidence import. Add `Import Evidence…` on the project/history surface. |
| Inspector | `Views/RunDetailView.swift` | Reuse for imported runs; add imported-evidence labels rather than a second database. |
| Limits already in force | `EvaluationStore.maximumCases` / `maximumPlannedSamples` = 100; `maximumTextFileBytes` = 5_000_000 | Capture limits live in `CaptureLimits`. When mapping into `EvaluationRun`, keep the tighter workbench cap. |
| Portable package | Root `Package.swift` (`FoundationEvalsPortable`) | Unchanged. New package is `Packages/FoundationEvalsIntegration`. |

## New types (not present in this checkout)

Package transport, capture writer, Apple codecs, `EvidenceImportService`, `EvidenceImportMapper`, `ConnectedFeatureLauncher`, `EvidenceImportView`, and `Examples/ConnectedFeature`.

## Native SDK note

Xcode 27.0 (27A266a). `Evaluations.framework` is not in the macOS SDK; it lives next to XCTest at `$(DEVELOPER_DIR)/Platforms/MacOSX.platform/Developer/Library/Frameworks/Evaluations.framework`. The app, unit tests, and `FoundationEvalsAppleBridge` link that copy. `EvaluationResult(jsonData:)` and `saveJSON(to:includeReportMetadata:)` are available. `FoundationModels.Transcript` remains Codable.
