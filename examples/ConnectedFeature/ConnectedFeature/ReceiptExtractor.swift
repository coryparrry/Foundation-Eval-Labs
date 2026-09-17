import Foundation
import FoundationEvalsIntegration

/// Production receipt extractor used by both the example app and its capture tests.
///
/// Example-only bug: the first GBP amount after `Subtotal` is treated as the paid total.
/// Fix that parser, not the captured output, to change later observations.
public struct ReceiptExtractor: FeatureUnderTest, Sendable {
    public init() {}

    public func evaluate(_ input: ReceiptInput) async throws -> ReceiptOutput {
        let lines = input.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let shopName = lines.first else {
            throw ReceiptExtractorError.emptyReceipt
        }
        let date = lines.compactMap(Self.date(from:)).first
        guard let totalPence = Self.buggyPaidTotalPence(in: lines) else {
            throw ReceiptExtractorError.missingTotal
        }
        return ReceiptOutput(shopName: shopName, date: date, totalPence: totalPence)
    }

    private static func date(from line: String) -> String? {
        let prefix = "Date:"
        guard line.hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func buggyPaidTotalPence(in lines: [String]) -> Int? {
        if let subtotal = lines.first(where: { $0.hasPrefix("Subtotal:") }) {
            return pence(in: subtotal)
        }
        if let paid = lines.first(where: { $0.hasPrefix("Total paid:") }) {
            return pence(in: paid)
        }
        return nil
    }

    static func reviewedPaidTotalPence(in text: String) -> Int? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return lines.first(where: { $0.hasPrefix("Total paid:") }).flatMap(pence(in:))
    }

    private static func pence(in line: String) -> Int? {
        guard let match = line.range(of: #"GBP\s+([0-9]+)\.([0-9]{2})"#, options: .regularExpression) else {
            return nil
        }
        let token = String(line[match]).replacingOccurrences(of: "GBP", with: "").trimmingCharacters(in: .whitespaces)
        let parts = token.split(separator: ".")
        guard parts.count == 2, let pounds = Int(parts[0]), let pence = Int(parts[1]) else { return nil }
        return pounds * 100 + pence
    }
}

public enum ReceiptExtractorError: Error, LocalizedError {
    case emptyReceipt
    case missingTotal

    public var errorDescription: String? {
        switch self {
        case .emptyReceipt: "The receipt has no shop name."
        case .missingTotal: "The receipt has no total."
        }
    }
}
