import Foundation

/// Typed production-feature boundary. Expected answers never belong on `Input`.
public protocol FeatureUnderTest: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Codable & Sendable

    func evaluate(_ input: Input) async throws -> Output
}
