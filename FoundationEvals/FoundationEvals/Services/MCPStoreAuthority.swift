import Foundation
import UniformTypeIdentifiers

@MainActor
enum MCPStoreAuthority {
    static func make(store: EvaluationStore) -> MCPAuthority {
        MCPAuthority(
            call: { call in await handle(call, store: store) },
            readResource: { request in await read(request, store: store) }
        )
    }

    private static func handle(_ call: MCPToolCall, store: EvaluationStore) async -> MCPToolPayload {
        do {
            switch call {
            case .getState:
                return try state(store)
            case .replaceSuite(let arguments):
                let before = store.suiteRevision
                let revision = try store.replaceSuite(
                    suite(from: arguments.suite),
                    expectedRevision: arguments.expectedRevision,
                    confirmDeletes: arguments.confirmDeletes == true
                )
                return mutation(revision == before ? "duplicate" : "committed", ["revision": .string(revision)])
            case .uploadAttachment(let arguments):
                let result = try await store.importAttachment(
                    id: arguments.id,
                    name: arguments.name,
                    mediaType: arguments.mediaType,
                    data: arguments.dataBase64,
                    expectedRevision: arguments.expectedRevision
                )
                return mutation(result.duplicate ? "duplicate" : "committed", [
                    "attachment": attachmentMetadata(result.attachment),
                    "revision": .string(result.revision),
                    "textTruncated": .bool(result.truncated)
                ])
            case .removeAttachment(let arguments):
                let removed = try store.removeAttachment(id: arguments.id, expectedRevision: arguments.expectedRevision)
                return mutation(removed ? "committed" : "duplicate", ["attachmentID": .string(arguments.id.uuidString)])
            case .startRun(let arguments):
                let duplicate = store.runStatus(id: arguments.runID) != nil
                let operation = try store.startRun(id: arguments.runID, expectedRevision: arguments.expectedRevision)
                return mutation(duplicate ? "duplicate" : "committed", ["run": try json(operation)])
            case .getRun(let arguments):
                return try getRun(arguments, store: store)
            case .listRuns(let arguments):
                return try listRuns(arguments, store: store)
            case .cancelRun(let arguments):
                let previous = store.runStatus(id: arguments.runID)
                let operation = try store.cancelRun(id: arguments.runID)
                let duplicate = previous?.phase != .running
                return mutation(duplicate ? "duplicate" : "committed", ["run": try json(operation)])
            case .deleteRun(let arguments):
                let deleted = try store.deleteRunDurably(id: arguments.runID)
                return mutation(deleted ? "committed" : "duplicate", ["runID": .string(arguments.runID.uuidString)])
            }
        } catch {
            return failure(error)
        }
    }

    private static func read(_ request: MCPResourceRequest, store: EvaluationStore) async -> MCPResourcePayload {
        do {
            switch request {
            case .attachment(let id):
                let value = try store.attachmentData(id: id)
                let uri = "foundation-evals://attachments/\(id.uuidString)"
                if value.attachment.kind == .text {
                    guard let text = String(data: value.data, encoding: .utf8) else {
                        throw EvaluationStoreError.persistence("The extracted attachment text is not valid UTF-8.")
                    }
                    return .text(uri: uri, mimeType: "text/plain; charset=utf-8", text: text)
                }
                let mediaType = value.attachment.storedFilename
                    .flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension)?.preferredMIMEType }
                    ?? "application/octet-stream"
                return .blob(uri: uri, mimeType: mediaType, data: value.data)
            case .run(let id):
                let data = try store.canonicalRunData(id: id)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw EvaluationStoreError.persistence("The canonical run export is not valid UTF-8.")
                }
                return .text(
                    uri: "foundation-evals://runs/\(id.uuidString)",
                    mimeType: "application/json",
                    text: text
                )
            }
        } catch {
            return .failure(uri: resourceURI(request), code: errorCode(error), message: error.localizedDescription)
        }
    }

    private static func state(_ store: EvaluationStore) throws -> MCPToolPayload {
        let active = try store.activeRun.map { try json(store.runStatus(id: $0.id)!) } ?? .null
        return readPayload([
            "revision": .string(try store.currentSuiteRevision()),
            "suite": suiteJSON(store.suite),
            "attachments": .array(store.suite.attachments.map(attachmentMetadata)),
            "readinessBlocker": store.runBlocker.map(MCPJSONValue.string) ?? .null,
            "model": .object([
                "available": .bool(store.modelStatus.isAvailable),
                "label": .string(store.modelStatus.label),
                "detail": .string(store.modelStatus.detail),
                "capabilities": .array(store.selectedModelCapabilities.evaluationNames.map(MCPJSONValue.string))
            ]),
            "workload": .object([
                "plannedSamples": .integer(Int64(store.plannedSampleCount)),
                "plannedModelRequests": .integer(Int64(store.plannedRequestCount)),
                "plannedToolCalls": .integer(Int64(store.plannedToolCallLimit))
            ]),
            "limits": .object([
                "maximumCases": .integer(Int64(EvaluationStore.maximumCases)),
                "maximumPlannedSamples": .integer(Int64(EvaluationStore.maximumPlannedSamples)),
                "maximumAttachments": .integer(Int64(EvaluationStore.maximumAttachments)),
                "maximumImages": .integer(Int64(EvaluationStore.maximumImages)),
                "maximumFieldCharacters": .integer(Int64(EvaluationStore.maximumFieldCharacters)),
                "maximumCombinedSuiteCharacters": .integer(Int64(EvaluationStore.maximumCombinedSuiteCharacters)),
                "maximumRubricRequirements": .integer(4),
                "maximumRubricRequirementCharacters": .integer(Int64(EvaluationStore.maximumRubricRequirementCharacters)),
                "maximumExtractedTextCharacters": .integer(Int64(EvaluationStore.maximumExtractedTextCharacters)),
                "maximumTextOrPDFBytes": .integer(Int64(EvaluationStore.maximumTextFileBytes)),
                "maximumImageBytes": .integer(Int64(EvaluationStore.maximumImageBytes)),
                "maximumHTTPRequestBytes": .integer(16 * 1_024 * 1_024)
            ]),
            "activeRun": active
        ])
    }

    private static func getRun(_ arguments: MCPGetRunArguments, store: EvaluationStore) throws -> MCPToolPayload {
        guard let operation = store.runStatus(id: arguments.runID) else {
            throw EvaluationStoreError.resourceNotFound("Run")
        }
        if let run = store.run(with: arguments.runID) {
            let limit = arguments.limit ?? 50
            let offset = try pageOffset(arguments.cursor, count: run.results.count)
            let end = min(offset + limit, run.results.count)
            var object = try json(run).objectValue!
            object["phase"] = .string(operation.phase.rawValue)
            object["results"] = try json(Array(run.results[offset..<end]))
            object["skipped"] = try json(skippedSamples(in: run))
            object["nextCursor"] = end < run.results.count ? .string(cursor(end)) : .null
            return readPayload(["run": .object(object)])
        }

        _ = try pageOffset(arguments.cursor, count: 0)
        let active = store.activeRun!
        return readPayload(["run": .object([
            "id": .string(active.id.uuidString),
            "suiteRevision": .string(active.suiteRevision),
            "phase": .string(operation.phase.rawValue),
            "startedAt": .string(active.startedAt.ISO8601Format()),
            "completedAt": .null,
            "completedSamples": .integer(Int64(active.completedSamples)),
            "plannedSampleCount": .integer(Int64(active.totalSamples)),
            "plannedCases": try json(store.suite.cases),
            "results": .array([]),
            "skipped": .array([]),
            "nextCursor": .null
        ])])
    }

    private static func listRuns(_ arguments: MCPListRunsArguments, store: EvaluationStore) throws -> MCPToolPayload {
        var summaries: [MCPJSONValue] = []
        if let active = store.activeRun, let operation = store.runStatus(id: active.id) {
            summaries.append(.object([
                "id": .string(active.id.uuidString),
                "suiteName": .string(store.suite.name),
                "suiteVersion": .string(store.suite.version),
                "phase": .string(operation.phase.rawValue),
                "startedAt": .string(active.startedAt.ISO8601Format()),
                "completedAt": .null,
                "completedSamples": .integer(Int64(active.completedSamples)),
                "plannedSamples": .integer(Int64(active.totalSamples))
            ]))
        }
        summaries.append(contentsOf: store.runs.map { run in
            let phase = store.runStatus(id: run.id)!.phase
            return .object([
                "id": .string(run.id.uuidString),
                "suiteName": .string(run.suiteName),
                "suiteVersion": .string(run.suiteVersion),
                "phase": .string(phase.rawValue),
                "startedAt": .string(run.startedAt.ISO8601Format()),
                "completedAt": .string(run.completedAt.ISO8601Format()),
                "completedSamples": .integer(Int64(run.results.count)),
                "plannedSamples": .integer(Int64(run.plannedResultCount)),
                "passed": .integer(Int64(run.passedCount)),
                "failed": .integer(Int64(run.failedCount)),
                "errors": .integer(Int64(run.errorCount))
            ])
        })

        if let query = arguments.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            summaries = summaries.filter { summary in
                let object = summary.objectValue!
                return object["suiteName"]!.stringValue!.localizedCaseInsensitiveContains(query)
                    || object["suiteVersion"]!.stringValue!.localizedCaseInsensitiveContains(query)
            }
        }
        if let status = arguments.status, !status.isEmpty {
            guard EvaluationRunPhase(rawValue: status) != nil else {
                return .failure(code: "invalid_status", message: "Status must be a run phase returned by this tool.")
            }
            summaries = summaries.filter { $0.objectValue?["phase"]?.stringValue == status }
        }

        let limit = arguments.limit ?? 50
        let offset = try pageOffset(arguments.cursor, count: summaries.count)
        let end = min(offset + limit, summaries.count)
        return readPayload([
            "runs": .array(Array(summaries[offset..<end])),
            "nextCursor": end < summaries.count ? .string(cursor(end)) : .null
        ])
    }

    private static func suite(from declaration: MCPSuiteDeclaration) -> EvaluationSuite {
        var suite = EvaluationSuite()
        suite.name = declaration.name
        suite.version = declaration.version
        suite.instructions = declaration.instructions
        suite.criteria = declaration.rubricRequirements.joined(separator: "\n")
        suite.scoringMode = ScoringMode(rawValue: declaration.scoringMode.rawValue)!
        suite.repetitions = declaration.repetitions
        suite.cases = declaration.cases.map {
            EvaluationCase(id: $0.id, name: $0.name, prompt: $0.prompt, expected: $0.expected)
        }
        var configuration = EvaluationModelConfiguration()
        configuration.provider = .onDevice
        configuration.reasoningLevel = .automatic
        configuration.samplingMode = EvaluationSamplingMode(rawValue: declaration.modelConfiguration.samplingMode.rawValue)!
        configuration.temperatureEnabled = declaration.modelConfiguration.temperatureEnabled
        configuration.temperature = declaration.modelConfiguration.temperature
        configuration.seedEnabled = declaration.modelConfiguration.seedEnabled
        configuration.seed = declaration.modelConfiguration.seed
        configuration.topK = declaration.modelConfiguration.topK
        configuration.probabilityThreshold = declaration.modelConfiguration.probabilityThreshold
        configuration.maximumResponseTokens = declaration.modelConfiguration.maximumResponseTokens
        configuration.maximumInputTokens = declaration.modelConfiguration.maximumInputTokens
        configuration.referenceMode = EvaluationReferenceMode(rawValue: declaration.modelConfiguration.referenceMode.rawValue)!
        configuration.contextPolicy = EvaluationContextPolicy(rawValue: declaration.modelConfiguration.contextPolicy.rawValue)!
        configuration.maximumToolCalls = declaration.modelConfiguration.maximumToolCalls
        suite.modelConfiguration = configuration
        return suite
    }

    private static func suiteJSON(_ suite: EvaluationSuite) -> MCPJSONValue {
        let configuration = suite.modelConfiguration
        return .object([
            "name": .string(suite.name),
            "version": .string(suite.version),
            "instructions": .string(suite.instructions),
            "scoringMode": .string(suite.scoringMode.rawValue),
            "repetitions": .integer(Int64(suite.repetitions)),
            "rubricRequirements": .array(suite.rubricCriteria.map(MCPJSONValue.string)),
            "modelConfiguration": .object([
                "samplingMode": .string(configuration.samplingMode.rawValue),
                "temperatureEnabled": .bool(configuration.temperatureEnabled),
                "temperature": .number(configuration.temperature),
                "seedEnabled": .bool(configuration.seedEnabled),
                "seed": .unsigned(configuration.seed),
                "topK": .integer(Int64(configuration.topK)),
                "probabilityThreshold": .number(configuration.probabilityThreshold),
                "maximumResponseTokens": .integer(Int64(configuration.maximumResponseTokens)),
                "maximumInputTokens": configuration.maximumInputTokens.map { .integer(Int64($0)) } ?? .null,
                "referenceMode": .string(configuration.referenceMode.rawValue),
                "contextPolicy": .string(configuration.contextPolicy.rawValue),
                "maximumToolCalls": .integer(Int64(configuration.maximumToolCalls))
            ]),
            "cases": .array(suite.cases.map { item in
                .object([
                    "id": .string(item.id.uuidString),
                    "name": .string(item.name),
                    "prompt": .string(item.prompt),
                    "expected": .string(item.expected)
                ])
            })
        ])
    }

    private static func attachmentMetadata(_ attachment: EvaluationAttachment) -> MCPJSONValue {
        .object([
            "id": .string(attachment.id.uuidString),
            "name": .string(attachment.name),
            "kind": .string(attachment.kind.rawValue),
            "byteCount": .integer(Int64(attachment.byteCount)),
            "sha256": .string(attachment.sha256),
            "textTruncated": .bool(attachment.text?.hasSuffix("\n[File truncated during import.]") == true)
        ])
    }

    private struct SkippedSample: Encodable {
        var caseID: UUID
        var caseName: String
        var repetition: Int
    }

    private static func skippedSamples(in run: EvaluationRun) -> [SkippedSample] {
        guard let cases = run.plannedCases else { return [] }
        let completed = Set(run.results.map { "\($0.caseID.uuidString):\($0.repetition)" })
        return (1...run.repetitions).flatMap { repetition in
            cases.compactMap { item in
                completed.contains("\(item.id.uuidString):\(repetition)")
                    ? nil
                    : SkippedSample(caseID: item.id, caseName: item.name, repetition: repetition)
            }
        }
    }

    private static func mutation(_ outcome: String, _ fields: [String: MCPJSONValue]) -> MCPToolPayload {
        MCPToolPayload(structuredContent: .object(fields.merging(["outcome": .string(outcome)]) { current, _ in current }))
    }

    private static func readPayload(_ fields: [String: MCPJSONValue]) -> MCPToolPayload {
        MCPToolPayload(structuredContent: .object(fields.merging(["outcome": .string("read")]) { current, _ in current }))
    }

    private static func failure(_ error: Error) -> MCPToolPayload {
        let outcome: String
        var fields: [String: MCPJSONValue] = [
            "error": .object(["code": .string(errorCode(error)), "message": .string(error.localizedDescription)])
        ]
        switch error {
        case EvaluationStoreError.staleRevision(let current):
            outcome = "conflicted"
            fields["currentRevision"] = .string(current)
        case EvaluationStoreError.resourceConflict:
            outcome = "conflicted"
        default:
            outcome = "failed"
        }
        fields["outcome"] = .string(outcome)
        return MCPToolPayload(structuredContent: .object(fields), isError: true)
    }

    private static func errorCode(_ error: Error) -> String {
        switch error {
        case EvaluationStoreError.staleRevision: "stale_revision"
        case EvaluationStoreError.runBusy: "run_busy"
        case EvaluationStoreError.fileOperationBusy: "file_operation_busy"
        case EvaluationStoreError.invalidSuite: "invalid_suite"
        case EvaluationStoreError.deletionConfirmationRequired: "confirmation_required"
        case EvaluationStoreError.resourceConflict: "resource_conflict"
        case EvaluationStoreError.resourceNotFound: "not_found"
        case EvaluationStoreError.persistence: "persistence_failed"
        case MCPStoreAuthorityError.invalidCursor: "invalid_cursor"
        default: "invalid_request"
        }
    }

    private static func resourceURI(_ request: MCPResourceRequest) -> String {
        switch request {
        case .attachment(let id): "foundation-evals://attachments/\(id.uuidString)"
        case .run(let id): "foundation-evals://runs/\(id.uuidString)"
        }
    }

    private static func json<T: Encodable>(_ value: T) throws -> MCPJSONValue {
        try JSONDecoder().decode(MCPJSONValue.self, from: CanonicalJSON.data(for: value, prettyPrinted: false))
    }

    private static func cursor(_ offset: Int) -> String {
        Data("offset:\(offset)".utf8).base64EncodedString()
    }

    private static func pageOffset(_ cursor: String?, count: Int) throws -> Int {
        guard let cursor else { return 0 }
        guard let data = Data(base64Encoded: cursor),
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("offset:"),
              let offset = Int(text.dropFirst("offset:".count)),
              (0...count).contains(offset)
        else { throw MCPStoreAuthorityError.invalidCursor }
        return offset
    }
}

private enum MCPStoreAuthorityError: LocalizedError {
    case invalidCursor

    var errorDescription: String? { "The pagination cursor is invalid or stale." }
}
