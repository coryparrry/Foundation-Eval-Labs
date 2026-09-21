# IntentLabFixture

This intentionally small iOS 27 sample contains synthetic notes with ambiguous display names and stable IDs. `OpenNoteIntent` exposes a deterministic App Intent and shortcut; `SummarizeNoteIntent` calls the same production `SummaryService` that an app feature can register with FoundationEvalsDeveloper.

Generate the project with `xcodegen generate --spec project.yml`. A simulator or generic-device build verifies compilation. The recognised-text Siri lane is valid only after a signed run on a paired physical iPhone with Siri configured for the scenario language.

The `INTENT_LAB_TEST_SUPPORT` condition exists only in the sample Debug/test configuration. Test hooks must not be added to a distribution configuration.
