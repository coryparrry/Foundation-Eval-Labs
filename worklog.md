# Worklog

- Goal: build a simple macOS SwiftUI app for running Apple Foundation Models evaluations without Xcode.
- Scope: instructions, prompts, file context, repeatable cases, response scoring, local traces, and export.
- Current: implementation complete; reusable app packaged and installed in the user Applications folder.
- Verified: Xcode build-for-testing, 2/2 permanent tests, rendered macOS preview, packaged launch check, strict installed-app signature check, and a real model-judge UI run with separate subject/judge trace data.
- Steering: use Xcode MCP; keep the app simple; research correct eval and trace practices.
