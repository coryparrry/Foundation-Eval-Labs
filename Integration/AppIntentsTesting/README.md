# Intent Lab UI-test support

Add these Swift files to a signed iOS UI-test target that builds with Xcode 27 or newer. Keep the fixed XCTest identity `IntentLabScenarioTests/testIntentLabScenario`. Bundled `IntentLabScenario.json` and `IntentLabInvocation.json` resources remain a compatibility fallback, but Quick Connect supplies both payloads atomically through the invocation-specific `.xctestrun` environment.

Declare the integration contract as user-defined build settings on that UI-test target:

```text
INTENT_LAB_HARNESS_VERSION = intent-lab-v1
INTENT_LAB_HARNESS_CAPABILITIES = environment-payload fixture-reset invocation-correlation accessible-result direct-intent-output
```

The host builds once in isolated Derived Data, resolves the exact products named by Xcode's generated `.xctestrun`, binds their host-computed fingerprints into a fresh invocation, and runs exactly that test method with an invocation-specific sibling `.xctestrun`. Extend `IntentProbe` only with deliberate, typed output extraction needed by the app under test. Never reflect or serialize an entire `ResolvedIntentResult`.

`SiriProbe` needs a paired physical iPhone with Siri enabled for the test language and the app's shortcuts discoverable. A simulator build proves compilation only; it does not prove Siri behavior.

The harness resets and relaunches the synthetic fixture between the direct-intent and Siri lanes. Siri completion requires the declared visible state or a state transition, and a failure stores a checksummed screenshot alongside the JSON envelope. Required App Feature coverage is intentionally rejected by desktop preflight because this UI-test bundle only owns Intent Integration and Siri evidence.
