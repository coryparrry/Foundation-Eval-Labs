# Developer runner verification host

This development-only iPhone/iPad app exercises the public
`FoundationEvalsDeveloper` package without modifying another application. It
registers a deterministic echo, cancellable and timeout fixtures, and a real
Apple Foundation Models response that reports an explicit availability failure.

Generate the local Xcode project with `xcodegen generate`, then build or run the
`DeveloperRunnerTestHost` scheme on an explicitly selected development device.
Pass the appropriate `DEVELOPMENT_TEAM` at build time instead of storing a
developer account identifier in this verification project.
Use `DeveloperRunnerTestHostMac` for desktop-only transport checks that do not
claim iPhone or iPad execution evidence.
The generated `.xcodeproj` is disposable and should not be committed. Launching
with `--auto-pair` starts one explicit pairing session for automated verification.
