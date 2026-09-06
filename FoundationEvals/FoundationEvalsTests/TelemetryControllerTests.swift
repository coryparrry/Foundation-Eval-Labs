import Foundation
import Testing
@testable import FoundationEvals

@MainActor struct TelemetryControllerTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "TelemetryTests.\(UUID().uuidString)")! }
    private let configuration = TelemetryConfiguration(projectToken: "phc_test", host: "https://us.i.posthog.com")

    @Test func freshStartupNeverCreatesClientOrCaptures() {
        let client = RecordingTelemetryClient()
        var creations = 0
        let controller = TelemetryController(defaults: defaults(), configuration: configuration) { _ in
            creations += 1
            return client
        }
        controller.capture(.appOpened)
        #expect(!controller.isEnabled)
        #expect(creations == 0)
        #expect(client.events.isEmpty)
    }

    @Test func consentTransitionsCreateOnceDiscardAndUseNewClient() {
        let defaults = defaults()
        var clients: [RecordingTelemetryClient] = []
        let controller = TelemetryController(defaults: defaults, configuration: configuration) { _ in
            let client = RecordingTelemetryClient()
            clients.append(client)
            return client
        }
        controller.setEnabled(true)
        controller.setEnabled(true)
        controller.capture(.appOpened)
        #expect(clients.count == 1)
        #expect(clients[0].events == ["foundation_evals_app_opened"])
        #expect(defaults.bool(forKey: TelemetryController.consentKey))
        controller.setEnabled(false)
        controller.capture(.appOpened)
        #expect(clients[0].discardCount == 1)
        #expect(clients[0].events.count == 1)
        #expect(!defaults.bool(forKey: TelemetryController.consentKey))
        controller.setEnabled(true)
        controller.capture(.evaluationStarted(caseCount: 2, sampleCount: 3))
        #expect(clients.count == 2)
        #expect(clients[1].events == ["foundation_evals_evaluation_started"])
    }

    @Test func persistedConsentStartsClientButMissingConfigurationFailsClosed() {
        let defaults = defaults()
        defaults.set(true, forKey: TelemetryController.consentKey)
        var creations = 0
        let factory: (TelemetryConfiguration) -> any TelemetryClient = { _ in
            creations += 1
            return RecordingTelemetryClient()
        }
        let enabled = TelemetryController(defaults: defaults, configuration: configuration, makeClient: factory)
        #expect(enabled.isEnabled)
        #expect(creations == 1)
        let missing = TelemetryController(defaults: defaults, configuration: nil, makeClient: factory)
        missing.setEnabled(true)
        #expect(!missing.isEnabled)
        #expect(!missing.isConfigured)
        #expect(creations == 1)
    }

    @Test func eventAllowlistExcludesContentAndNormalizesCountsAndDuration() {
        #expect(TelemetryEvent.allowedProperties(for: "$screen") == nil)
        #expect(TelemetryEvent.allowedProperties(for: "$exception") == nil)
        let event = TelemetryEvent.evaluationFinished(outcome: .failed, sampleCount: -1, durationSeconds: .infinity)
        #expect(event.properties["outcome"] as? String == "failed")
        #expect(event.properties["sample_count"] as? Int == 0)
        #expect(event.properties["duration_seconds"] as? Double == 0)
        for name in ["foundation_evals_app_opened", "foundation_evals_evaluation_started", "foundation_evals_evaluation_finished"] {
            let allowed = TelemetryEvent.allowedProperties(for: name)!
            #expect(allowed.isDisjoint(with: ["prompt", "response", "error", "provider_url", "$device_id", "$os_version", "$screen_name"]))
        }
    }
}

@MainActor private final class RecordingTelemetryClient: TelemetryClient {
    var events: [String] = []
    var discardCount = 0
    func capture(_ event: TelemetryEvent) { events.append(event.name) }
    func stopAndDiscard() { discardCount += 1 }
}

@Suite(.serialized) struct TelemetryTransportTests {
    @Test func uploadBodySurvivesAndRemoteConfigIsBlocked() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryRecordingProtocol.self]
        TelemetryRecordingProtocol.clear()
        let transport = TelemetryTransport(host: "https://telemetry.invalid", sessionConfiguration: configuration)
        defer { transport.stop() }
        let session = URLSession(configuration: transport.configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://telemetry.invalid/batch")!)
        request.httpMethod = "POST"
        let payload = Data("{\"batch\":[{\"event\":\"foundation_evals_app_opened\"}]}".utf8)
        _ = try await session.upload(for: request, from: payload)
        #expect(TelemetryRecordingProtocol.bodies() == [payload])
        do {
            _ = try await session.data(from: URL(string: "https://telemetry.invalid/flags")!)
            Issue.record("Feature flags must be blocked")
        } catch { }
        #expect(TelemetryRecordingProtocol.bodies().count == 1)
    }

    @Test func revokedSessionCannotSendAfterNewConsent() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryRecordingProtocol.self]
        TelemetryRecordingProtocol.clear()
        let old = TelemetryTransport(host: "https://telemetry.invalid", sessionConfiguration: configuration)
        let oldSession = URLSession(configuration: old.configuration)
        old.stop()
        let current = TelemetryTransport(host: "https://telemetry.invalid", sessionConfiguration: configuration)
        defer { current.stop(); oldSession.invalidateAndCancel() }
        let currentSession = URLSession(configuration: current.configuration)
        defer { currentSession.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://telemetry.invalid/batch")!)
        request.httpMethod = "POST"
        do {
            _ = try await oldSession.upload(for: request, from: Data("old".utf8))
            Issue.record("Revoked transport must stay blocked")
        } catch { }
        _ = try await currentSession.upload(for: request, from: Data("new".utf8))
        #expect(TelemetryRecordingProtocol.bodies() == [Data("new".utf8)])
    }
}

private final class TelemetryRecordingProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [Data] = []
    static func clear() { lock.withLock { captured = [] } }
    static func bodies() -> [Data] { lock.withLock { captured } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
        }
        Self.lock.withLock { Self.captured.append(body) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
