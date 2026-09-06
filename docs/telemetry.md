# Optional telemetry

Telemetry is off until a user enables **Settings → Privacy → Share usage statistics**.
The app does not initialize PostHog before consent. Consent persists across app launches.
No consent prompt blocks evaluation or setup.

## Events and data

| Event | Properties |
| --- | --- |
| `foundation_evals_app_opened` | App version and macOS major version |
| `foundation_evals_evaluation_started` | Case count and planned sample count, plus versions |
| `foundation_evals_evaluation_finished` | Completed sample count, rounded duration in seconds, and `completed`, `cancelled`, or `failed`, plus versions |

Each event carries a random analytics identifier. It is not linked to a name,
email address, Apple account, suite, or provider. Run identifiers and timestamps
from evaluation content are not included; PostHog receives the event's own timestamp.
A failed outcome means an execution/provider error, not a low evaluation score.

The event allowlist excludes prompts, responses, reference files, suite names,
provider addresses, credentials, error messages, device names, and session properties.
Automatic lifecycle/screen/interaction capture, error capture, person profiles,
feature-flag events, and session recording are disabled. Remote configuration
requests are blocked. IP-based geolocation is disabled; the receiving service still
necessarily handles the network connection's source address.

Turning telemetry off cancels pending requests, discards unsent events, and resets
the analytics identifier. It cannot recall requests already received by PostHog
and does not delete historical events there.

## Project and configuration

Foundation Evals uses the existing EU PostHog project **Default project (266962)**.
Event names have a `foundation_evals_` prefix to separate them from other apps.
The public ingestion token and EU ingest host are stored in `Configuration/AppInfo.plist`.
This token grants event ingestion; it is not a personal API key and cannot read
project analytics. Builds with missing configuration keep the switch disabled.

The pinned official Swift SDK handles event batching. A per-consent transport only
allows event uploads to the configured HTTPS host; revocation closes that transport.
Delivery is best effort: pending batches from an interrupted or short prior session
are discarded on launch. SDK upgrades must recheck queue cleanup, property filtering,
and upload behavior.

## Verification

Run `TelemetryControllerTests`, `TelemetryTransportTests`, and
`EvaluationStoreRunLifecycleTests` in the native Xcode test target. Controller tests
cover default-off, opt-in, opt-out, re-enabling, and missing configuration. Run tests
against isolated defaults and storage. Never enable live telemetry in unattended tests.

Before a release, exercise the Privacy switch in the built app: confirm default-off,
opt in, run a fixture, and check the prefixed events and their properties in PostHog.
Then turn it off and confirm another fixture produces no new events. A successful
HTTP response alone does not prove PostHog ingestion.

[PostHog Swift SDK documentation](https://posthog.com/docs/libraries/ios)

## Integration evidence (2026-09-06)

Nine focused native tests passed: consent/allowlist, transport, and evaluation
lifecycle (including provider failure and persistence retry). The Debug app built
and its Privacy switch was verified off by default. With isolated evaluation
storage and consent on, the EU project received one app-open, one evaluation-start,
and one evaluation-finish event with outcome `completed`. After turning consent
off, a second evaluation completed and all three counts stayed at one; the SDK
store was removed. Consent was left off. This verifies development runtime
integration, not a notarized release artifact.
