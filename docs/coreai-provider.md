# Core AI provider integration

FoundationEvals links Apple's `CoreAILM` Swift package product and imports the
`CoreAILanguageModels` module. The model entry point is:

```swift
let model = try await CoreAILanguageModel(resourcesAt: resourcesURL, mode: .eager)
```

The app uses eager loading so a run never reports readiness from metadata alone.
Only after the engine and tokenizer load successfully does the loader expose the
model name, declared context length, loaded model capabilities, and model asset
size.

## Pinned revision

The dependency is pinned to Apple commit
`684ae8e6a6766ff1dcb3dfa9c598b7eef44d2b43`, the final revision before the
package added a conflicting exact Hummingbird dependency.

The `0.2.0` tag cannot compile against the installed Xcode 27 beta 6 Foundation
Models SDK. It uses the former labeled `LanguageModelCapabilities(capabilities:)`
initializer and former `prewarm(transcript:) throws` executor requirement. Beta 6
provides `LanguageModelCapabilities(_:)` and requires
`prewarm(model:transcript:)`. Apple adopted those signatures after 0.2.0 in
commit `5ed9981303b38d5a44aa6b45509bc4f6945029f5`.

The selected revision includes that SDK migration, lazy/eager resource loading,
the public `LanguageBundle.maxContextLength` metadata API, and exact XGrammar
`0.2.2`. It does not include the later package-level Hummingbird `2.22.0` exact
constraint, which conflicts with FoundationEvals' direct Hummingbird `2.26.0`
requirement.

Primary sources:

- [Apple coreai-models](https://github.com/apple/coreai-models)
- [CoreAILanguageModel source](https://github.com/apple/coreai-models/blob/684ae8e6a6766ff1dcb3dfa9c598b7eef44d2b43/swift/Sources/CoreAILanguageModels/LanguageModel/CoreAILanguageModel.swift)
- [LanguageBundle source](https://github.com/apple/coreai-models/blob/684ae8e6a6766ff1dcb3dfa9c598b7eef44d2b43/swift/Sources/CoreAILanguageModels/Bundle/LanguageBundle.swift)
- [Foundation Models API migration](https://github.com/apple/coreai-models/commit/5ed9981303b38d5a44aa6b45509bc4f6945029f5)

## Resource boundary

The picker accepts an exported Core AI resource folder. The folder must contain
the `metadata.json` bundle description, referenced `.aimodel` assets, and the
tokenizer resources required by the selected model. A security-scoped bookmark
is stored with the suite configuration so the app can reopen a selected folder.

No compatible model resources are checked into this repository or currently
known on the host. Missing, inaccessible, non-folder, stale-bookmark, malformed,
tokenizer, and engine-creation failures are surfaced as loading errors. Actual
inference validation remains pending until a resource folder is selected.
