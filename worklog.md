# Workspace reset controls

- Request: add ways to clear previous traces and reset the current evaluation suite.
- Added a toolbar menu with suite reset, history clearing, and combined reset; each requires an explicit destructive confirmation and is disabled during active operations.
- Blank suites persist canonically while execution still requires a prompt. History clearing removes stored JSON and obsolete recovery markers, and reloads history even after partial deletion failure.
- Verified: Xcode BuildProject(buildForTesting: true); four WorkspaceResetTests; WorkflowTraceUITests/testWorkspaceResetConfirmationAndPersistence(); git diff --check. All targeted tests passed after fixing test-fixture setup and macOS sheet lookup.
- Inspected the native reset screenshot; Xcode RunProject launched the updated app successfully.
