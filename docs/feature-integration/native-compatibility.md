# Native compatibility

Recorded on the development Mac used to implement Feature 1.

| Item | Value |
|---|---|
| Xcode | 27.0 (27A266a) |
| Swift | 6.4 (swiftlang-6.4.0.34.1) |
| SDK | macOS 27 |
| Runtime OS | macOS 27.0 (26A428) |
| Evaluations.framework | `$(DEVELOPER_DIR)/Platforms/MacOSX.platform/Developer/Library/Frameworks/Evaluations.framework` |
| `EvaluationResult(jsonData:)` | Available |
| `EvaluationResult.saveJSON(to:includeReportMetadata:)` | Available; `to` is a directory |
| `.evaluates` | Available; subject is not run a second time in the test body |
| `Transcript` Codable | Available |
| Live on-device model | Reported by `SystemLanguageModel` availability; unavailable hosts must not record a fake live pass |

Controlled fixture coverage in `Examples/ConnectedFeature`:

- Returned output with a failing paid-total check (discounted receipt)
- Subject throw
- Evaluator throw after the subject returned
- Ignored metric plus a non-rubric numeric score
- Empty transcript encode/decode

Sanitised exports are written to `Examples/ConnectedFeature/Fixtures/` when those tests run. They contain no personal receipts.
