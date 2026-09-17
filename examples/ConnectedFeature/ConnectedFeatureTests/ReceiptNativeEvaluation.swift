import Evaluations
import Foundation
import FoundationEvalsIntegration
@testable import ConnectedFeature

struct ReceiptNativeEvaluation: Evaluation {
    typealias Sample = ModelSample<ReceiptOutput>
    typealias Subject = ModelSubject<ReceiptOutput>
    typealias SampleLoader = ArrayLoader<Sample>

    let paidTotal = Metric("paidTotal")
    let ignoredDemo = Metric("ignoredDemo")
    let penceScale = Metric("penceScale")
    let counter: CallCounter?

    init(counter: CallCounter? = nil) {
        self.counter = counter
    }

    var dataset: ArrayLoader<Sample> {
        ArrayLoader(samples: Self.samples)
    }

    static let samples: [ModelSample<ReceiptOutput>] = [
        ModelSample(
            prompt: ReceiptFixtures.ordinary.text,
            expected: ReceiptOutput(shopName: "Example Shop", date: "2026-09-01", totalPence: 1000)
        ),
        ModelSample(
            prompt: ReceiptFixtures.discounted.text,
            expected: ReceiptOutput(shopName: "Example Shop", date: "2026-09-01", totalPence: 750)
        ),
        ModelSample(
            prompt: "SUBJECT_THROW\nEmpty",
            expected: ReceiptOutput(shopName: "Example Shop", date: nil, totalPence: 100)
        ),
        ModelSample(
            prompt: "EVALUATOR_THROW\nExample Shop\nSubtotal: GBP 1.00\nTotal paid: GBP 1.00",
            expected: ReceiptOutput(shopName: "Example Shop", date: nil, totalPence: 100)
        ),
    ]

    func subject(from sample: ModelSample<ReceiptOutput>) async throws -> ModelSubject<ReceiptOutput> {
        counter?.increment()
        let prompt = sample.input.promptDescription
        if prompt.contains("SUBJECT_THROW") {
            throw ReceiptExtractorError.emptyReceipt
        }
        return ModelSubject(value: try await ReceiptExtractor().evaluate(ReceiptInput(text: prompt)))
    }

    var evaluators: Evaluators {
        Evaluator { (input: Sample, subject: Subject) in
            if input.input.promptDescription.contains("EVALUATOR_THROW") {
                throw ReceiptExtractorError.missingTotal
            }
            guard let expected = input.expected else {
                return paidTotal.ignore(rationale: "Check ignored · Not evidence of a pass")
            }
            if subject.value.totalPence == expected.totalPence {
                return paidTotal.passing(rationale: "Paid total matched \(expected.totalPence) pence")
            }
            return paidTotal.failing(
                rationale: "Producer-reported check failed: \(subject.value.totalPence) != \(expected.totalPence)"
            )
        }
        Evaluator { (_: Sample, _: Subject) in
            ignoredDemo.ignore(rationale: "Check ignored · Not evidence of a pass")
        }
        Evaluator { (_: Sample, _: Subject) in
            penceScale.scoring(99, rationale: "Pence scale; not a 1-4 rubric")
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: paidTotal)
    }
}

func exportEvaluation<E: Evaluation>(
    _ evaluation: E,
    directory: URL,
    metadata: [String: String]
) async throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let result = try await evaluation.run(info: metadata)
    return try result.saveJSON(to: directory, includeReportMetadata: true)
}
