import Foundation
@_exported import FoundationEvalsIntegration

public struct ReceiptInput: Codable, Hashable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ReceiptOutput: Codable, Hashable, Sendable {
    public var shopName: String
    public var date: String?
    public var totalPence: Int

    public init(shopName: String, date: String?, totalPence: Int) {
        self.shopName = shopName
        self.date = date
        self.totalPence = totalPence
    }
}

public enum ReceiptFeature {
    public static let appID = "com.coryparry.ConnectedFeature"
    public static let featureID = "receipt-extractor"
    public static let inputRevision = "receipt-text-v1"
}
