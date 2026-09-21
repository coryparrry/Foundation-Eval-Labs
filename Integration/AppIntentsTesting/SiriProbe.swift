import XCTest

@MainActor
enum SiriProbe {
    static func run(
        request: String,
        application: XCUIApplication,
        expectedContext: String,
        safety: IntentLabSafety
    ) throws -> [String: IntentLabValue] {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SiriProbeError.missingRequest
        }
        XCUIDevice.shared.siriService.activate(voiceRecognitionText: request)
        let context = application.staticTexts["intent-lab-observed-context"]
        guard context.waitForExistence(timeout: 2) else { throw SiriProbeError.fixtureUnavailable }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expectedContext),
            object: context
        )
        guard XCTWaiter.wait(for: [expectation], timeout: waitTimeout(for: safety)) == .completed else {
            throw SiriProbeError.outcomeNotObserved
        }
        guard var observations = correlatedCompletion(
            observations: FixtureBridge.observations(from: application),
            expectedContext: expectedContext
        ) else {
            throw SiriProbeError.invocationNotCorrelated
        }
        observations["recognizedRequest"] = .string(request)
        return observations
    }

    static func waitTimeout(for safety: IntentLabSafety) -> TimeInterval {
        safety.deadlineSeconds
    }

    static func correlatedCompletion(
        observations: [String: IntentLabValue],
        expectedContext: String
    ) -> [String: IntentLabValue]? {
        observations["invocationContext"] == .string(expectedContext) ? observations : nil
    }
}

enum SiriProbeError: LocalizedError {
    case missingRequest
    case fixtureUnavailable
    case outcomeNotObserved
    case invocationNotCorrelated
    var errorDescription: String? {
        switch self {
        case .missingRequest: "The approved Siri request is empty."
        case .fixtureUnavailable: "The synthetic fixture did not expose its baseline observation."
        case .outcomeNotObserved: "Siri did not establish the declared visible outcome before the deadline."
        case .invocationNotCorrelated: "The application outcome was not correlated to this scenario attempt."
        }
    }
}
