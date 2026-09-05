import Foundation
import Testing
@testable import FoundationEvals

struct MCPFeatureTests {
    @MainActor
    @Test func explicitFeaturesRoundTripThroughSuiteReplacementAndState() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let authority = MCPStoreAuthority.make(store: store)
        let features = featureConfiguration()
        let arguments = try MCPJSONValue.encode(MCPReplaceSuiteArguments(
            expectedRevision: store.suiteRevision,
            confirmDeletes: true,
            suite: suiteDeclaration(name: "Feature suite", features: features)
        ))

        let call = try MCPToolCatalog.parse(name: "eval_replace_suite", arguments: arguments)
        let replacement = await authority.call(call)
        #expect(
            replacement.structuredContent.objectValue?["outcome"] == .string("committed"),
            "Unexpected replacement payload: \((try? replacement.structuredContent.jsonText()) ?? "unencodable")"
        )
        #expect(store.suite.features == features)

        let state = await authority.call(.getState).structuredContent.objectValue
        let reportedFeatures = try #require(state?["suite"]?.objectValue?["features"])
        #expect(try reportedFeatures.decode(EvaluationFeatureConfiguration.self) == features)

        let limits = try #require(state?["limits"]?.objectValue)
        let workload = try #require(state?["workload"]?.objectValue)
        #expect(workload["plannedToolCalls"] == .integer(4))
        #expect(limits["maximumCustomTools"] == .integer(4))
        #expect(limits["maximumToolParameters"] == .integer(8))
        #expect(limits["maximumOutputFields"] == .integer(8))
        #expect(limits["maximumToolOutputBytes"] == .integer(4_096))
        #expect(limits["maximumCustomToolOutputTokens"] == .integer(512))
        #expect(limits["maximumCustomToolArgumentTokens"] == .integer(256))
        #expect(limits["maximumToolArgumentsBytes"] == .integer(16_384))
    }

    @MainActor
    @Test func stateCountsReferenceAndCustomToolCallAllowancesTogether() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let attachmentID = UUID()
        _ = try await store.importAttachment(
            id: attachmentID,
            name: "reference.txt",
            mediaType: "text/plain",
            data: Data("Reference evidence".utf8),
            expectedRevision: store.suiteRevision
        )
        store.draftSuite.features = featureConfiguration()
        store.draftSuite.scoringMode = .review
        store.draftSuite.modelConfiguration.referenceMode = .lookupTool
        store.draftSuite.modelConfiguration.maximumToolCalls = 2
        store.draftSuite.modelConfiguration.maximumResponseTokens = 512
        store.draftSuite.repetitions = 2
        let validationIssue = store.validationIssue(for: store.draftSuite, includeModelReadiness: false)
        #expect(store.saveSuite(), "Suite was not saved: \(validationIssue ?? "unknown validation issue")")

        let state = await MCPStoreAuthority.make(store: store).call(.getState).structuredContent.objectValue
        let workload = try #require(state?["workload"]?.objectValue)
        #expect(workload["plannedSamples"] == .integer(2))
        #expect(workload["plannedToolCalls"] == .integer(8))
    }

    @MainActor
    @Test func omittedFeaturesPreserveTheStoredConfigurationForLegacyClients() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let existingFeatures = featureConfiguration()
        store.draftSuite.features = existingFeatures
        #expect(store.saveSuite())
        let authority = MCPStoreAuthority.make(store: store)
        let arguments = try MCPJSONValue.encode(MCPReplaceSuiteArguments(
            expectedRevision: store.suiteRevision,
            confirmDeletes: true,
            suite: suiteDeclaration(name: "Legacy replacement", features: nil)
        ))

        #expect(arguments.objectValue?["suite"]?.objectValue?["features"] == nil)
        let call = try MCPToolCatalog.parse(name: "eval_replace_suite", arguments: arguments)
        let replacement = await authority.call(call)

        #expect(
            replacement.structuredContent.objectValue?["outcome"] == .string("committed"),
            "Unexpected replacement payload: \((try? replacement.structuredContent.jsonText()) ?? "unencodable")"
        )
        #expect(store.suite.name == "Legacy replacement")
        #expect(store.suite.features == existingFeatures)
    }

    @Test func featureArgumentsRejectUnknownFieldsAndEnumValues() throws {
        var unknownFieldArguments = try featureArguments()
        var suite = try #require(unknownFieldArguments.objectValue?["suite"]?.objectValue)
        var features = try #require(suite["features"]?.objectValue)
        var tools = try #require(features["tools"]?.arrayValue)
        var tool = try #require(tools[0].objectValue)
        var parameters = try #require(tool["parameters"]?.arrayValue)
        var parameter = try #require(parameters[0].objectValue)
        parameter["undeclared"] = .bool(true)
        parameters[0] = .object(parameter)
        tool["parameters"] = .array(parameters)
        tools[0] = .object(tool)
        features["tools"] = .array(tools)
        suite["features"] = .object(features)
        var root = try #require(unknownFieldArguments.objectValue)
        root["suite"] = .object(suite)
        unknownFieldArguments = .object(root)

        #expect(throws: MCPToolInputError.self) {
            try MCPToolCatalog.parse(name: "eval_replace_suite", arguments: unknownFieldArguments)
        }

        var invalidEnumArguments = try featureArguments()
        suite = try #require(invalidEnumArguments.objectValue?["suite"]?.objectValue)
        features = try #require(suite["features"]?.objectValue)
        tools = try #require(features["tools"]?.arrayValue)
        tool = try #require(tools[0].objectValue)
        tool["mode"] = .string("remoteHTTP")
        tools[0] = .object(tool)
        features["tools"] = .array(tools)
        suite["features"] = .object(features)
        root = try #require(invalidEnumArguments.objectValue)
        root["suite"] = .object(suite)
        invalidEnumArguments = .object(root)

        #expect(throws: MCPToolInputError.self) {
            try MCPToolCatalog.parse(name: "eval_replace_suite", arguments: invalidEnumArguments)
        }

        var nullFeatureArguments = try featureArguments()
        suite = try #require(nullFeatureArguments.objectValue?["suite"]?.objectValue)
        suite["features"] = .null
        root = try #require(nullFeatureArguments.objectValue)
        root["suite"] = .object(suite)
        nullFeatureArguments = .object(root)
        #expect(throws: MCPToolInputError.self) {
            try MCPToolCatalog.parse(name: "eval_replace_suite", arguments: nullFeatureArguments)
        }
    }

    @Test func featureModelValidationRejectsUnsafeEndpointsAndKnownLimitViolations() throws {
        for endpoint in [
            "https://example.com:8443/tool",
            "http://localhost:19000/tool",
            "http://127.0.0.1:17873/tool",
            "http://127.0.0.1/tool"
        ] {
            var features = featureConfiguration()
            features.tools[1].endpoint = endpoint
            #expect(throws: MCPToolInputError.self) {
                try MCPToolCatalog.parse(
                    name: "eval_replace_suite",
                    arguments: try featureArguments(features: features)
                )
            }
        }

        var tooManyTools = featureConfiguration()
        tooManyTools.tools = (0...EvaluationFeatureConfiguration.maximumTools).map { index in
            EvaluationCustomToolDefinition(
                name: "tool_\(index)",
                description: "Fixture tool \(index)",
                fixtureResponse: "ok"
            )
        }
        #expect(throws: MCPToolInputError.self) {
            try MCPToolCatalog.parse(
                name: "eval_replace_suite",
                arguments: try featureArguments(features: tooManyTools)
            )
        }

        var oversizedOutput = featureConfiguration()
        oversizedOutput.tools[0].fixtureResponse = String(
            repeating: "é",
            count: EvaluationCustomToolDefinition.maximumOutputBytes / 2 + 1
        )
        #expect(oversizedOutput.tools[0].fixtureResponse.count < EvaluationCustomToolDefinition.maximumOutputBytes)
        #expect(throws: MCPToolInputError.self) {
            try MCPToolCatalog.parse(
                name: "eval_replace_suite",
                arguments: try featureArguments(features: oversizedOutput)
            )
        }
    }

    private func featureArguments(
        features: EvaluationFeatureConfiguration? = nil
    ) throws -> MCPJSONValue {
        try MCPJSONValue.encode(MCPReplaceSuiteArguments(
            expectedRevision: "revision",
            confirmDeletes: false,
            suite: suiteDeclaration(
                name: "Feature suite",
                features: features ?? featureConfiguration()
            )
        ))
    }

    private func suiteDeclaration(
        name: String,
        features: EvaluationFeatureConfiguration?
    ) -> MCPSuiteDeclaration {
        MCPSuiteDeclaration(
            name: name,
            version: "1",
            instructions: "Use configured features.",
            scoringMode: .review,
            repetitions: 1,
            rubricRequirements: ["Useful"],
            modelConfiguration: MCPModelConfiguration(
                samplingMode: .automatic,
                temperatureEnabled: false,
                temperature: 0,
                seedEnabled: false,
                seed: 0,
                topK: 40,
                probabilityThreshold: 0.9,
                maximumResponseTokens: 512,
                maximumInputTokens: nil,
                referenceMode: .inline,
                contextPolicy: .fitReferences,
                maximumToolCalls: 4
            ),
            features: features,
            cases: [MCPCaseDeclaration(id: UUID(), name: "Case", prompt: "Evaluate this.", expected: "")]
        )
    }

    private func featureConfiguration() -> EvaluationFeatureConfiguration {
        let query = EvaluationSchemaField(
            name: "query",
            description: "Lookup query",
            type: .string
        )
        return EvaluationFeatureConfiguration(
            tools: [
                EvaluationCustomToolDefinition(
                    name: "fixture_lookup",
                    description: "Return a canned lookup result.",
                    parameters: [query],
                    mode: .fixture,
                    fixtureResponse: #"{"result":"fixture"}"#
                ),
                EvaluationCustomToolDefinition(
                    name: "local_lookup",
                    description: "Execute the developer-configured local lookup.",
                    parameters: [query],
                    mode: .localHTTP,
                    endpoint: "http://127.0.0.1:19000/tool"
                )
            ],
            profile: EvaluationProfileConfiguration(
                enabled: true,
                name: "Lookup first",
                afterToolInstructions: "Use the returned evidence in the final answer.",
                requireToolFirst: true
            ),
            outputFields: [
                EvaluationSchemaField(
                    name: "answer",
                    description: "Final answer",
                    type: .string
                ),
                EvaluationSchemaField(
                    name: "confidence",
                    description: "Confidence from zero to one",
                    type: .number,
                    isOptional: true
                )
            ],
            prewarm: true,
            streamResponse: true
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MCPFeatureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private extension MCPJSONValue {
    var arrayValue: [MCPJSONValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }
}
