import CryptoKit
import Foundation
import FoundationEvalsIntegration

enum EvidenceImportMapper {
    static func mappedCaseID(appID: String, featureID: String, sourceCaseID: String) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data("foundation-evals-case-v1".utf8))
        hasher.update(data: [0])
        hasher.update(data: Data(appID.utf8))
        hasher.update(data: [0])
        hasher.update(data: Data(featureID.utf8))
        hasher.update(data: [0])
        hasher.update(data: Data(sourceCaseID.utf8))
        let digest = Array(hasher.finalize())
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    static func run(
        from bundle: CaptureBundle,
        destinationProjectID: UUID,
        destinationSuiteID: UUID,
        suiteName: String,
        importedAt: Date = Date()
    ) throws -> EvaluationRun {
        let producer = bundle.manifest.producer
        var sourceCaseIDs: [String: String] = [:]
        var checks: [EvaluationImportedCheck] = []
        var notes: [EvaluationImportedSampleNote] = []
        var transcriptEntries: [EvaluationImportedTranscriptEntry] = []
        let plannedCases: [EvaluationCase] = bundle.manifest.plan.cases.map { item in
            let id = mappedCaseID(appID: producer.appID, featureID: producer.featureID, sourceCaseID: item.caseID)
            sourceCaseIDs[id.uuidString] = item.caseID
            return EvaluationCase(
                id: id,
                name: item.caseID,
                prompt: (try? item.input.utf8Text()) ?? "",
                expected: ""
            )
        }
        let results: [EvaluationSampleResult] = try bundle.observations.map { observation in
            let caseID = mappedCaseID(
                appID: producer.appID,
                featureID: producer.featureID,
                sourceCaseID: observation.coordinate.caseID
            )
            sourceCaseIDs[caseID.uuidString] = observation.coordinate.caseID
            let sampleID = observation.observationID
            let labels = labels(for: observation)
            for check in observation.checks {
                checks.append(
                    EvaluationImportedCheck(
                        sampleID: sampleID,
                        name: check.name,
                        status: check.status.rawValue,
                        label: label(for: check),
                        rationale: check.rationale,
                        semantics: check.semantics,
                        value: check.value.map(displayJSON),
                        evaluator: check.evaluator
                    )
                )
            }
            if observation.checks.isEmpty, observation.execution == .returned {
                checks.append(
                    EvaluationImportedCheck(
                        sampleID: sampleID,
                        name: "execution",
                        status: "unknown",
                        label: EvaluationImportedLabels.notAssessed,
                        rationale: nil,
                        semantics: nil,
                        value: nil,
                        evaluator: nil
                    )
                )
            }
            let partial = try observation.partialOutput.map(displayJSON)
            if observation.captureError != nil || partial != nil || observation.transcriptRelativePath != nil {
                notes.append(
                    EvaluationImportedSampleNote(
                        sampleID: sampleID,
                        partialOutput: partial,
                        captureError: observation.captureError?.message,
                        transcriptRelativePath: observation.transcriptRelativePath
                    )
                )
            }
            if let path = observation.transcriptRelativePath {
                transcriptEntries.append(contentsOf: loadTranscriptEntries(from: bundle, relativePath: path, sampleID: sampleID))
            }
            let responseText: String
            if let returned = try? response(for: observation), !returned.isEmpty {
                responseText = returned
            } else {
                responseText = partial ?? ""
            }
            return EvaluationSampleResult(
                id: sampleID,
                caseID: caseID,
                caseName: observation.coordinate.caseID,
                repetition: observation.coordinate.repetition,
                prompt: try observation.input.utf8Text(),
                expected: "",
                response: responseText,
                status: observation.execution == .threw || observation.captureError != nil ? .error : .unscored,
                score: nil,
                rationale: labels.joined(separator: " · "),
                durationMilliseconds: observation.durationMilliseconds,
                usage: EvaluationUsage(),
                errorCategory: observation.captureError?.kind ?? observation.error.map(\.kind),
                errorMessage: observation.captureError?.message ?? observation.error?.message,
                judgeErrorCategory: observation.evaluatorError.map(\.kind),
                judgeErrorMessage: observation.evaluatorError?.message
            )
        }
        let coverageLabel: String
        if bundle.coverage.isComplete {
            coverageLabel = "\(bundle.coverage.observedCount) of \(bundle.coverage.plannedCount) planned observations"
        } else {
            coverageLabel = EvaluationImportedLabels.incompleteCapture
        }
        var warnings = bundle.warnings
        warnings.insert(EvaluationImportedLabels.inspectionOnly, at: 0)
        let environment = bundle.manifest.environment
        return EvaluationRun(
            id: UUID(),
            suiteID: destinationSuiteID,
            suiteName: suiteName,
            suiteVersion: "imported",
            instructions: "",
            criteria: "",
            scoringMode: .review,
            repetitions: 1,
            plannedSampleCount: bundle.manifest.plan.cases.isEmpty ? nil : bundle.manifest.plan.cases.count,
            plannedCases: plannedCases,
            startedAt: bundle.manifest.run.startedAt,
            completedAt: bundle.manifest.run.endedAt ?? importedAt,
            cancelled: bundle.manifest.run.state == .cancelled,
            terminationReason: bundle.manifest.run.state == .stopped || !bundle.coverage.isComplete
                ? EvaluationImportedLabels.incompleteCapture
                : nil,
            environment: EvaluationEnvironment(
                operatingSystem: environment.operatingSystem,
                locale: environment.locale,
                model: environment.model ?? "Imported evidence",
                modelContextSize: 0
            ),
            attachments: [],
            results: results,
            projectID: destinationProjectID,
            importedEvidence: EvaluationImportedEvidence(
                sourceKind: .captureBundle,
                eligibility: CaptureImportEligibility.inspectionOnly.rawValue,
                producerAppID: producer.appID,
                producerFeatureID: producer.featureID,
                producerRunID: bundle.manifest.run.runID.uuidString,
                sourceDigest: bundle.manifestDigest,
                manifestDigest: bundle.manifestDigest,
                importedAt: importedAt,
                captureStartedAt: bundle.manifest.run.startedAt,
                captureEndedAt: bundle.manifest.run.endedAt,
                warnings: warnings,
                coverageLabel: coverageLabel,
                environmentClaims: environmentClaims(environment),
                importerHost: importerHost(),
                originalRelativePath: "",
                rerunOf: bundle.manifest.run.rerunOf,
                sourceCaseIDs: sourceCaseIDs,
                transcriptAvailable: !transcriptEntries.isEmpty || bundle.observations.contains { $0.transcriptRelativePath != nil },
                checks: checks,
                sourcePlan: bundle.manifest.plan,
                transcriptEntries: transcriptEntries,
                sampleNotes: notes
            )
        )
    }

    static func run(
        from inspection: AppleEvaluationInspection,
        destinationProjectID: UUID,
        destinationSuiteID: UUID,
        suiteName: String,
        importedAt: Date = Date()
    ) -> EvaluationRun {
        let results: [EvaluationSampleResult] = inspection.samples.enumerated().map { index, sample in
            let caseID = mappedCaseID(appID: "apple-evaluation", featureID: inspection.evaluationID, sourceCaseID: String(index))
            let sampleID = UUID()
            return EvaluationSampleResult(
                id: sampleID,
                caseID: caseID,
                caseName: "Row \(index + 1)",
                repetition: 1,
                prompt: sample.fields["input"] ?? sample.fields.values.sorted().first ?? "",
                expected: sample.fields["expected"] ?? "",
                response: sample.fields["response"] ?? sample.fields["output"] ?? "",
                status: sample.subjectError == nil ? .unscored : .error,
                rationale: [
                    EvaluationImportedLabels.plannedUnknown,
                    EvaluationImportedLabels.inspectionOnly,
                    sample.evaluatorError.map { _ in "Evaluator failed separately from the subject" },
                    sample.metrics.contains(where: { $0.kind == "fail" }) ? EvaluationImportedLabels.producerCheckFailed : nil,
                    sample.metrics.contains(where: { $0.kind == "ignore" }) ? EvaluationImportedLabels.ignoredCheck : nil,
                    EvaluationImportedLabels.originalFileOnly,
                ].compactMap { $0 }.joined(separator: " · "),
                durationMilliseconds: 0,
                usage: EvaluationUsage(),
                errorCategory: sample.subjectError == nil ? nil : "subject",
                errorMessage: sample.subjectError,
                judgeErrorCategory: sample.evaluatorError == nil ? nil : "evaluator",
                judgeErrorMessage: sample.evaluatorError
            )
        }
        let checks: [EvaluationImportedCheck] = zip(inspection.samples, results).flatMap { sample, result in
            sample.metrics.map { metric in
                EvaluationImportedCheck(
                    sampleID: result.id,
                    name: metric.name,
                    status: metric.kind,
                    label: metricLabel(metric.kind),
                    rationale: metric.rationale,
                    semantics: metric.kind,
                    value: metric.value,
                    evaluator: metric.evaluatorKind
                )
            }
        }
        var warnings = [EvaluationImportedLabels.inspectionOnly] + inspection.warnings
        if inspection.samples.isEmpty, !warnings.contains(EvaluationImportedLabels.metadataOnly) {
            warnings.insert(EvaluationImportedLabels.metadataOnly, at: 0)
        }
        return EvaluationRun(
            id: UUID(),
            suiteID: destinationSuiteID,
            suiteName: suiteName,
            suiteVersion: "imported",
            instructions: "",
            criteria: "",
            scoringMode: .review,
            repetitions: 1,
            plannedSampleCount: nil,
            startedAt: inspection.startedAt,
            completedAt: inspection.endedAt,
            cancelled: false,
            terminationReason: nil,
            environment: EvaluationEnvironment(
                operatingSystem: inspection.evaluationInfo["os"] ?? "Unknown producer OS",
                locale: inspection.evaluationInfo["locale"] ?? "",
                model: inspection.evaluationInfo["model"] ?? "Apple evaluation result",
                modelContextSize: 0
            ),
            attachments: [],
            results: results,
            projectID: destinationProjectID,
            importedEvidence: EvaluationImportedEvidence(
                sourceKind: .appleEvaluationResult,
                eligibility: CaptureImportEligibility.inspectionOnly.rawValue,
                producerAppID: inspection.evaluationInfo["app"],
                producerFeatureID: inspection.evaluationID,
                producerRunID: inspection.resultID.uuidString,
                sourceDigest: inspection.digest,
                manifestDigest: nil,
                importedAt: importedAt,
                captureStartedAt: inspection.startedAt,
                captureEndedAt: inspection.endedAt,
                warnings: warnings,
                coverageLabel: inspection.samples.isEmpty ? EvaluationImportedLabels.metadataOnly : EvaluationImportedLabels.plannedUnknown,
                environmentClaims: inspection.evaluationInfo,
                importerHost: importerHost(),
                originalRelativePath: "",
                rerunOf: nil,
                sourceCaseIDs: [:],
                transcriptAvailable: false,
                checks: checks
            )
        )
    }

    static func run(
        from inspection: AppleTranscriptInspection,
        destinationProjectID: UUID,
        destinationSuiteID: UUID,
        suiteName: String,
        importedAt: Date = Date()
    ) -> EvaluationRun {
        let entries = inspection.entries.map {
            EvaluationImportedTranscriptEntry(sampleID: nil, id: $0.id, kind: $0.kind, text: $0.text, toolName: $0.toolName)
        }
        let prompt = inspection.entries.filter { $0.kind == "prompt" }.compactMap(\.text).joined(separator: "\n")
        let response = inspection.entries.filter { $0.kind == "response" }.compactMap(\.text).joined(separator: "\n")
        let tools = inspection.entries.compactMap(\.toolName)
        let result = EvaluationSampleResult(
            id: UUID(),
            caseID: mappedCaseID(appID: "apple-transcript", featureID: "transcript", sourceCaseID: inspection.digest),
            caseName: "Transcript",
            repetition: 1,
            prompt: prompt,
            expected: "",
            response: response,
            status: .unscored,
            rationale: [EvaluationImportedLabels.bareTranscript, EvaluationImportedLabels.inspectionOnly].joined(separator: " · "),
            durationMilliseconds: 0,
            usage: EvaluationUsage(),
            toolCalls: tools.isEmpty ? nil : tools.enumerated().map {
                EvaluationToolCallTrace(toolName: $1, callIndex: $0, matchedFiles: [], outputCharacterCount: 0, outcome: "imported")
            }
        )
        return EvaluationRun(
            id: UUID(),
            suiteID: destinationSuiteID,
            suiteName: suiteName,
            suiteVersion: "imported",
            instructions: "",
            criteria: "",
            scoringMode: .review,
            repetitions: 1,
            plannedSampleCount: nil,
            startedAt: importedAt,
            completedAt: importedAt,
            cancelled: false,
            terminationReason: nil,
            environment: EvaluationEnvironment(
                operatingSystem: "Unknown producer OS",
                locale: "",
                model: "Apple transcript",
                modelContextSize: 0
            ),
            attachments: [],
            results: [result],
            projectID: destinationProjectID,
            importedEvidence: EvaluationImportedEvidence(
                sourceKind: .appleTranscript,
                eligibility: CaptureImportEligibility.inspectionOnly.rawValue,
                producerAppID: nil,
                producerFeatureID: nil,
                producerRunID: inspection.digest,
                sourceDigest: inspection.digest,
                manifestDigest: nil,
                importedAt: importedAt,
                captureStartedAt: nil,
                captureEndedAt: nil,
                warnings: [EvaluationImportedLabels.bareTranscript, EvaluationImportedLabels.inspectionOnly] + inspection.warnings,
                coverageLabel: EvaluationImportedLabels.plannedUnknown,
                environmentClaims: [:],
                importerHost: importerHost(),
                originalRelativePath: "",
                rerunOf: nil,
                sourceCaseIDs: [:],
                transcriptAvailable: !inspection.entries.isEmpty,
                checks: [],
                transcriptEntries: entries
            )
        )
    }

    private static func response(for observation: CaptureObservation) throws -> String {
        switch observation.output {
        case .absent:
            return ""
        case .returned(let value):
            return try value.utf8Text()
        }
    }

    private static func labels(for observation: CaptureObservation) -> [String] {
        var labels = [EvaluationImportedLabels.inspectionOnly]
        if observation.execution == .returned, observation.checks.isEmpty {
            labels.append(EvaluationImportedLabels.notAssessed)
        }
        if observation.checks.contains(where: { $0.status == .failed }) {
            labels.append(EvaluationImportedLabels.producerCheckFailed)
        }
        if observation.checks.contains(where: { $0.status == .ignored }) {
            labels.append(EvaluationImportedLabels.ignoredCheck)
        }
        if observation.transcriptRelativePath == nil {
            labels.append(EvaluationImportedLabels.transcriptMissing)
        }
        if observation.transcriptError != nil {
            labels.append("Transcript capture failed")
        }
        return labels
    }

    private static func label(for check: CaptureCheck) -> String {
        switch check.status {
        case .failed: EvaluationImportedLabels.producerCheckFailed
        case .ignored: EvaluationImportedLabels.ignoredCheck
        case .passed: "Producer-reported check passed"
        case .error: "Producer-reported check error"
        case .unknown: EvaluationImportedLabels.notAssessed
        }
    }

    private static func displayJSON(_ value: CaptureJSON) -> String {
        if case .string(let text) = value { return text }
        if case .number(let literal) = value { return literal }
        return (try? value.utf8Text(prettyPrinted: false)) ?? ""
    }

    private static func metricLabel(_ kind: String) -> String {
        switch kind {
        case "fail": EvaluationImportedLabels.producerCheckFailed
        case "ignore": EvaluationImportedLabels.ignoredCheck
        case "pass": "Producer-reported check passed"
        case "score": "Producer-reported metric value"
        default: EvaluationImportedLabels.notAssessed
        }
    }

    private static func loadTranscriptEntries(
        from bundle: CaptureBundle,
        relativePath: String,
        sampleID: UUID
    ) -> [EvaluationImportedTranscriptEntry] {
        guard let url = try? CaptureFileIO.resolvedMember(root: bundle.root, relativePath: relativePath),
              let data = try? CaptureFileIO.readRegularFileNoFollow(
                at: url,
                maximumBytes: CaptureLimits.version1.maximumAppleJSONBytes
              ),
              let inspection = try? AppleTranscriptCodec.inspect(bytes: data) else {
            return [
                EvaluationImportedTranscriptEntry(
                    sampleID: sampleID,
                    id: relativePath,
                    kind: "unavailable",
                    text: "The linked transcript could not be opened from \(relativePath).",
                    toolName: nil
                )
            ]
        }
        return inspection.entries.map {
            EvaluationImportedTranscriptEntry(
                sampleID: sampleID,
                id: $0.id,
                kind: $0.kind,
                text: $0.text,
                toolName: $0.toolName
            )
        }
    }

    private static func environmentClaims(_ environment: CaptureEnvironment) -> [String: String] {
        var claims: [String: String] = [
            "operatingSystem": environment.operatingSystem,
            "locale": environment.locale,
        ]
        if let device = environment.device { claims["device"] = device }
        if let revision = environment.sourceRevision { claims["sourceRevision"] = revision }
        if let dirty = environment.workingTreeDirty { claims["workingTreeDirty"] = dirty ? "true" : "false" }
        if let model = environment.model { claims["model"] = model }
        if !environment.unknowns.isEmpty { claims["unknowns"] = environment.unknowns.joined(separator: ",") }
        return claims
    }

    private static func importerHost() -> [String: String] {
        [
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "locale": Locale.current.identifier,
        ]
    }
}
