import Foundation
import Security

enum MCPBearerTokenStoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidStoredToken
    case randomGeneration(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain:
            "The MCP credential could not be accessed in Keychain."
        case .invalidStoredToken:
            "The stored MCP credential is invalid. Rotate it and try again."
        case .randomGeneration:
            "A secure MCP credential could not be generated."
        }
    }
}

struct MCPBearerTokenStore: Sendable {
    private let service: String
    private let account: String

    init(
        service: String = "com.coryparry.FoundationEvals.mcp",
        account: String = "loopback-bearer-token"
    ) {
        self.service = service
        self.account = account
    }

    func loadOrCreate() async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            if let existing = try loadSynchronously() { return existing }
            let token = try generate()
            try saveSynchronously(token)
            return token
        }.value
    }

    func load() async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            try loadSynchronously()
        }.value
    }

    private func loadSynchronously() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw MCPBearerTokenStoreError.keychain(status)
        }
        guard let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw MCPBearerTokenStoreError.invalidStoredToken
        }
        guard (try? CodexMCPConfiguration(bearerToken: token)) != nil else {
            throw MCPBearerTokenStoreError.invalidStoredToken
        }
        return token
    }

    func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw MCPBearerTokenStoreError.randomGeneration(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func save(_ token: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try saveSynchronously(token)
        }.value
    }

    private func saveSynchronously(_ token: String) throws {
        _ = try CodexMCPConfiguration(bearerToken: token)
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw MCPBearerTokenStoreError.keychain(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MCPBearerTokenStoreError.keychain(addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
