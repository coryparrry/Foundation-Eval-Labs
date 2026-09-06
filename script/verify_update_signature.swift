import CryptoKit
import Foundation

// Verify downloaded update bytes independently of feed metadata and code signing.
do {
    guard CommandLine.arguments.count == 4,
          let publicKey = Data(base64Encoded: CommandLine.arguments[2]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "UpdateVerification", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Expected installer, public key, and signature."])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "UpdateVerification", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Sparkle installer signature is invalid."])
    }
    print("Sparkle installer signature verified.")
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
