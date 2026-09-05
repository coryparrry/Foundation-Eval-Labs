import Foundation

struct EvaluationLiveResponse: Sendable, Equatable {
    var caseID: UUID
    var caseName: String
    var repetition: Int
    var turnName: String
    var content: String
}
