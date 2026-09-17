import Foundation
import FoundationEvalsIntegration

public enum ReceiptFixtures {
    public static let ordinary = ReceiptCase(
        id: "receipt-ordinary-v1",
        name: "Ordinary receipt",
        text: """
        Example Shop
        Date: 2026-09-01
        Subtotal: GBP 10.00
        Total paid: GBP 10.00
        """,
        expectedTotalPence: 1000
    )

    public static let discounted = ReceiptCase(
        id: "receipt-discounted-v1",
        name: "Discounted receipt",
        text: """
        Example Shop
        Date: 2026-09-01
        Subtotal: GBP 10.00
        Discount: GBP 2.50
        Total paid: GBP 7.50
        """,
        expectedTotalPence: 750
    )

    public static let missingDate = ReceiptCase(
        id: "receipt-missing-date-v1",
        name: "Missing date",
        text: """
        Example Shop
        Subtotal: GBP 4.00
        Total paid: GBP 4.00
        """,
        expectedTotalPence: 400
    )

    public static let reviewed: [ReceiptCase] = [ordinary, discounted, missingDate]

    public static func plan() throws -> CapturePlan {
        CapturePlan(
            cases: try reviewed.map { item in
                CapturePlanCase(
                    caseID: item.id,
                    inputRevision: ReceiptFeature.inputRevision,
                    input: try CaptureJSON.fromEncoded(ReceiptInput(text: item.text))
                )
            }
        )
    }

    public static func expectations() -> [CaptureExpectation] {
        reviewed.map { item in
            CaptureExpectation(
                caseID: item.id,
                inputRevision: ReceiptFeature.inputRevision,
                expected: .object(["totalPence": .number(String(item.expectedTotalPence))]),
                reviewProvenance: "Reviewed example fixture; not production input."
            )
        }
    }

    public static func launchCases() throws -> [CaptureLaunchCase] {
        try reviewed.map { item in
            CaptureLaunchCase(
                caseID: item.id,
                inputRevision: ReceiptFeature.inputRevision,
                input: try CaptureJSON.fromEncoded(ReceiptInput(text: item.text))
            )
        }
    }
}

public struct ReceiptCase: Sendable, Equatable {
    public var id: String
    public var name: String
    public var text: String
    public var expectedTotalPence: Int
}
