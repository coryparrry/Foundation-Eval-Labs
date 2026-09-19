# Developer integration, device execution, and dashboard

## Ownership

Astra owns SwiftUI presentation, visual inspection, and final integration on
`codex/developer-dashboard`. Sol high owns SDK, runner, transport, persistence,
backend tests, and build configuration in an isolated worktree. Neither lane
reverts unrelated changes. Sol sends a completion message; Astra does not poll.

## Swift integration

1. Package a public Swift integration that registers real feature closures while
   preserving the developer's Foundation Models types and tools inside their app.
2. Define versioned request/result contracts, feature discovery, cancellation,
   errors, and ownership. Integrate with existing persisted evaluation evidence.
3. Include a runnable sample, setup documentation, and meaningful contract tests.
   Investigate Apple's Evaluations interoperability against the installed SDK;
   document supported boundaries rather than inventing APIs.

## Device execution

1. Add explicit pairing and trusted runner connections for macOS/iOS/iPadOS.
2. Record actual device/OS/runner identity with each dispatched run. Support
   availability, disconnect, timeout, cancellation, and reconnect behavior.
3. Expose a small observable interface for the desktop's connection list and run
   target picker. Keep local evaluation available and never fabricate devices.
4. Validate transport and persistence, compile the sample runner, and distinguish
   fixture/simulator proof from physical-device execution. Do not install on or
   change a user's physical device without an appropriate explicit selection.

## Dashboard UI

1. Inspect current native UI and the supplied component/motion references.
2. Refine the project overview with a coherent header, truthful summary metrics,
   readable suite cards/table, recent activity, and clear primary actions.
3. Refine sidebar, suite results/comparison entry points, and connection/device
   presentation using reusable native SwiftUI components. No fabricated charts
   or unsupported claims; distinguish unavailable, unscored, and failed results.
4. Use modest state-driven motion, accessible controls, Reduce Motion handling,
   adaptive layout, and both light/dark appearance.
5. Build and inspect actual rendered screens and relevant interactions. Fix
   requirement failures with at most two visual fix/recheck rounds.

## Integration and verification

Sol commits its scoped work and reports the commit, public UI contracts, exact
validation, and remaining limitations to the parent task. Astra integrates the
commit into the dashboard branch, connects the presentation, builds, and visually
checks the integrated UI. Backend corrections remain Sol's responsibility.
No publication, release, or claim of physical-device proof is implied.

## UI checkpoint — 19 September 2026

Implemented the project dashboard, metric cards, suite search/attention filter,
latest-check navigation, suite-health summary, sidebar refinement, and run-history
presentation. Components use semantic system colours and Reduce Motion-aware
transitions. SwiftUX's Tickets Sales Dashboard and Inspora's Support analytics
informed grouping and density; supplied library repositories were reviewed, with
no third-party implementation copied or new runtime dependency required.

Validation: macOS Debug `xcodebuild` passed after both visual correction rounds;
`git diff --check` passed. The actual app was inspected with isolated storage:
created starter suites, completed a three-case on-device receipt run, checked
search/filter states, cross-suite latest-run navigation, and final result labels.
A Luna High read-only review found three issues; all were corrected and rechecked.
Light appearance was visually verified. Dark/compact SwiftUI preview rendering
hit an Xcode timeout, so these appearances remain unverified.

SDK/device presentation and final integration remain pending Sol's completion
message. No backend changes or physical-device execution are claimed by this UI
checkpoint. The parent task stops here without polling the backend task.
