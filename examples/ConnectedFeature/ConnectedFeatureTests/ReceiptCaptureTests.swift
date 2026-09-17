import Foundation
import FoundationEvalsIntegration
import Testing
@testable import ConnectedFeature

struct ReceiptCaptureTests {
    @Test func appAndTestsShareProductionEntry() async throws {
        let output = try await ReceiptExtractor().evaluate(ReceiptInput(text: ReceiptFixtures.discounted.text))
        #expect(output.shopName == "Example Shop")
        #expect(output.totalPence == 1000)
        #expect(ReceiptExtractor.reviewedPaidTotalPence(in: ReceiptFixtures.discounted.text) == 750)
    }

    @Test func captureWritesVersion1Bundle() async throws {
        let request = try ConnectedFeatureHandoff.loadRequestSnapshot()
        let outputParent: URL
        let runID: UUID
        let rerunOf: UUID?
        let plan: CapturePlan
        if let request {
            let job = try request.validatedJobDirectory(projectRoot: ConnectedFeatureHandoff.projectRoot)
            outputParent = job
            runID = request.runID
            rerunOf = request.parentRunID
            plan = CapturePlan(
                cases: request.cases.map {
                    CapturePlanCase(
                        caseID: $0.caseID,
                        inputRevision: $0.inputRevision,
                        repetition: $0.repetition,
                        featureVariant: $0.featureVariant,
                        input: $0.input
                    )
                }
            )
        } else {
            outputParent = FileManager.default.temporaryDirectory.appending(path: "connected-feature-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: outputParent, withIntermediateDirectories: true)
            runID = UUID()
            rerunOf = nil
            plan = try ReceiptFixtures.plan()
        }

        let writer = try CaptureBundleWriter(
            runID: runID,
            rerunOf: rerunOf,
            outputParent: outputParent,
            producer: .init(appID: ReceiptFeature.appID, featureID: ReceiptFeature.featureID),
            plan: plan,
            environment: .currentHost(featureConfigurationID: ReceiptFeature.featureID),
            expectations: ReceiptFixtures.expectations()
        )
        let session = CaptureSession(feature: ReceiptExtractor(), writer: writer)
        let published = try await session.run(plan: plan)
        let bundle = try CaptureBundleValidator.load(root: published)
        #expect(bundle.eligibility == .inspectionOnly)
        #expect(bundle.observations.count == plan.cases.count)

        let discounted = bundle.observations.first { $0.coordinate.caseID == ReceiptFixtures.discounted.id }
        #expect(discounted?.execution == .returned)
        if case .returned(let value) = discounted?.output, case .object(let object) = value {
            #expect(object["totalPence"] == .number("1000"))
        } else {
            Issue.record("Discounted observation did not keep the production output.")
        }
        if let expected = bundle.expectations.first(where: { $0.caseID == ReceiptFixtures.discounted.id }) {
            #expect(expected.expected != discounted.map { outputJSON($0) })
        }
    }

    private func outputJSON(_ observation: CaptureObservation) -> CaptureJSON? {
        if case .returned(let value) = observation.output { return value }
        return nil
    }
}
