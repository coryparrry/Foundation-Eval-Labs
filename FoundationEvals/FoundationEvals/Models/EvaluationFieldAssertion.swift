import Foundation

enum EvaluationFieldAssertionOperation: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case exists, equals, containsText, minimum, maximum
    var id: Self { self }
    var title: String {
        switch self {
        case .exists: "Exists"
        case .equals: "Equals JSON value"
        case .containsText: "Contains text"
        case .minimum: "Number ≥"
        case .maximum: "Number ≤"
        }
    }
}

struct EvaluationFieldAssertion: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var pointer = ""
    var operation = EvaluationFieldAssertionOperation.exists
    var expectedValue = ""
}

struct EvaluationFieldAssertionResult: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { assertion.id }
    var assertion: EvaluationFieldAssertion
    var passed: Bool
    var actualJSON: String?
    var explanation: String
}
