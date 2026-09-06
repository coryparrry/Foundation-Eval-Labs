import Foundation
import Testing
@testable import FoundationEvals

struct EvaluationStoreRunLifecycleTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func exactMatchRunCompletesPersistsReloadsAndAnalyzes() async throws {
        let fixture = try LifecycleCustomModelFixture()
        defer { fixture.stop() }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let runID = UUID()
        let evaluationCase = EvaluationCase(
            name: "Deterministic response",
            prompt: "Return the fixture response.",
            expected: "Deterministic fixture stream."
        )
        let store = EvaluationStore(supportDirectory: directory)
        store.draftSuite.name = "Lifecycle fixture"
        store.draftSuite.scoringMode = .exactMatch
        store.draftSuite.cases = [evaluationCase]
        store.draftSuite.repetitions = 1
        store.draftSuite.modelConfiguration.provider = .customHTTP
        store.draftSuite.modelConfiguration.customProviderSettings.endpoint = fixture.endpoint(path: "/text")

        #expect(store.saveSuite())
        let revision = try store.currentSuiteRevision()
        let started = try store.startRun(id: runID, expectedRevision: revision)
        #expect(started.phase == .running)
        #expect(started.totalSamples == 1)

        try await waitForRunToFinish(in: store)

        let completed = try #require(store.run(with: runID))
        let result = try #require(completed.results.first)
        #expect(completed.results.count == 1)
        #expect(completed.terminationReason == nil)
        #expect(!completed.cancelled)
        #expect(result.response == evaluationCase.expected)
        #expect(result.status == .passed)
        #expect(result.errorCategory == nil)
        #expect(store.runStatus(id: runID)?.phase == .completed)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "active-run.json").path))
        #expect(FileManager.default.fileExists(
            atPath: directory.appending(path: "Runs/\(runID.uuidString).json").path
        ))

        let reloadedStore = EvaluationStore(supportDirectory: directory)
        let reloadedRun = try #require(reloadedStore.run(with: runID))
        #expect(reloadedRun.suiteRevision == revision)
        #expect(reloadedRun.results.first?.response == evaluationCase.expected)
        #expect(reloadedRun.results.first?.status == .passed)
        #expect(reloadedRun.execution?.configuration == store.suite.modelConfiguration)

        let analysis = EvaluationRunAnalysis(run: reloadedRun)
        #expect(analysis.runID == runID)
        #expect(analysis.plannedSampleCount == 1)
        #expect(analysis.completedSampleCount == 1)
        #expect(analysis.missingSampleCount == 0)
        #expect(analysis.scoredSampleCount == 1)
        #expect(analysis.passedSampleCount == 1)
        #expect(analysis.failedSampleCount == 0)
        #expect(analysis.errorSampleCount == 0)
        #expect(analysis.scoredPassRate == 1)
        #expect(analysis.subjectUsage.requestCount == 1)
        #expect(analysis.subjectUsage.outputTokens == 4)
        #expect(analysis.cases.first?.caseID == evaluationCase.id)
        #expect(analysis.cases.first?.repetitionVariation == .insufficientScoredSamples)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func providerFailurePersistsStoppedRunForReloadAndAnalysis() async throws {
        let fixture = try LifecycleCustomModelFixture()
        defer { fixture.stop() }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let runID = UUID()
        let store = EvaluationStore(supportDirectory: directory)
        store.draftSuite.scoringMode = .review
        store.draftSuite.repetitions = 2
        store.draftSuite.modelConfiguration.provider = .customHTTP
        store.draftSuite.modelConfiguration.customProviderSettings.endpoint = fixture.endpoint(path: "/error")

        #expect(store.saveSuite())
        let revision = try store.currentSuiteRevision()
        _ = try store.startRun(id: runID, expectedRevision: revision)
        try await waitForRunToFinish(in: store)

        let stopped = try #require(store.run(with: runID))
        #expect(stopped.results.count == 1)
        #expect(stopped.plannedResultCount == 2)
        #expect(stopped.terminationReason == "customProviderError")
        #expect(stopped.stoppedEarly)
        #expect(!stopped.cancelled)
        #expect(stopped.results.first?.status == .error)
        #expect(stopped.results.first?.errorCategory == "customProviderError")
        #expect(store.runStatus(id: runID)?.phase == .stopped)

        let reloadedStore = EvaluationStore(supportDirectory: directory)
        let reloadedRun = try #require(reloadedStore.run(with: runID))
        #expect(reloadedStore.runStatus(id: runID)?.phase == .stopped)
        #expect(reloadedRun.terminationReason == "customProviderError")
        #expect(reloadedRun.results.first?.errorCategory == "customProviderError")

        let analysis = EvaluationRunAnalysis(run: reloadedRun)
        #expect(analysis.plannedSampleCount == 2)
        #expect(analysis.completedSampleCount == 1)
        #expect(analysis.missingSampleCount == 1)
        #expect(analysis.scoredSampleCount == 0)
        #expect(analysis.errorSampleCount == 1)
        #expect(analysis.cases.first?.missingSampleCount == 1)
        #expect(analysis.cases.first?.errorSampleCount == 1)
    }

    @MainActor
    private func waitForRunToFinish(in store: EvaluationStore) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while store.isRunning {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for the evaluation store run to finish.")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "EvaluationStoreRunLifecycleTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class LifecycleCustomModelFixture {
    let port: Int
    private let process: Process

    init() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repository.appending(path: "examples/custom_model_fixture_server.py")
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, "--port", "0", "--stream-delay", "0"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        self.process = process

        let readyData = output.fileHandleForReading.availableData
        guard let ready = String(data: readyData, encoding: .utf8),
              let firstLine = ready.split(separator: "\n").first,
              let endpoint = firstLine.split(separator: " ").last,
              let port = URL(string: String(endpoint))?.port else {
            process.terminate()
            process.waitUntilExit()
            throw LifecycleCustomModelFixtureError.invalidReadyMessage
        }
        self.port = port
    }

    func endpoint(path: String) -> String {
        "http://127.0.0.1:\(port)\(path)"
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}

private enum LifecycleCustomModelFixtureError: Error {
    case invalidReadyMessage
}
