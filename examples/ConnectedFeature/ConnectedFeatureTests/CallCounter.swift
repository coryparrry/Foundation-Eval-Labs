import Foundation
import FoundationEvalsIntegration
import os

final class CallCounter: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func reset() {
        lock.withLock { $0 = 0 }
    }

    func increment() {
        lock.withLock { $0 += 1 }
    }

    var value: Int {
        lock.withLock { $0 }
    }
}

enum ReceiptNativeTrait {
    static let counter = CallCounter()
}
