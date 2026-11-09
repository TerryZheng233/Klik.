import CryptoKit
import Foundation

enum UpdateSignature {
    // The matching private key stays in the release owner's Keychain.
    static let publicKey = Data(base64Encoded: "vj9cJYOjtG6HLEKzL6QVZVXkxPoLN2zej+1PKwutLq0=")!

    static func message(version: String, filename: String, sha256: String) -> Data {
        Data("Klik update v1\n\(version)\n\(filename)\n\(sha256)\n".utf8)
    }

    static func verify(signature: Data, version: String, filename: String, sha256: String,
                       publicKey: Data = publicKey) -> Bool {
        guard let text = String(data: signature, encoding: .utf8), signature.count <= 256,
              let signatureBytes = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signatureBytes, for: message(version: version, filename: filename, sha256: sha256))
    }
}
