#!/usr/bin/swift
import CryptoKit
import Foundation
import Security

let service = "local.klik.update-signing"
let account = "ed25519-v1"
let expectedPublicKey = "vj9cJYOjtG6HLEKzL6QVZVXkxPoLN2zej+1PKwutLq0="
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service,
                            kSecAttrAccount as String: account,
                            kSecReturnData as String: true,
                            kSecMatchLimit as String: kSecMatchLimitOne]
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
func loadKey() throws -> Curve25519.Signing.PrivateKey? {
    var item: CFTypeRef?
    let result = SecItemCopyMatching(query as CFDictionary, &item)
    if result == errSecItemNotFound { return nil }
    guard result == errSecSuccess, let bytes = item as? Data else { fail("Keychain access failed (\(result)).") }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
}
let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "generate" {
    guard try loadKey() == nil else { fail("A signing key already exists. Use 'public' to view its public key; it will not be replaced.") }
    let key = Curve25519.Signing.PrivateKey()
    let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: account,
        kSecAttrLabel as String: "Klik update signing key (Ed25519)",
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecValueData as String: key.rawRepresentation]
    let result = SecItemAdd(attributes as CFDictionary, nil)
    guard result == errSecSuccess else { fail("Could not save signing key in Keychain (\(result)).") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else if arguments.count == 2 && arguments[1] == "public" {
    guard let key = try loadKey() else { fail("No update signing key exists in this Keychain.") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else if arguments.count == 5 && arguments[1] == "sign" {
    let version = arguments[2]
    let file = URL(fileURLWithPath: arguments[3])
    let output = URL(fileURLWithPath: arguments[4])
    let clean = version.hasPrefix("v") ? String(version.dropFirst()) : version
    let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
    guard version == "v" + clean, !parts.isEmpty, parts.count <= 4,
          parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
          file.lastPathComponent == "Klik-\(clean)-arm64.dmg" else { fail("Version or installer filename is invalid.") }
    guard let key = try loadKey() else { fail("No update signing key exists in this Keychain.") }
    guard key.publicKey.rawRepresentation.base64EncodedString() == expectedPublicKey else {
        fail("This key does not match Klik's pinned public key; refusing to sign an unusable release.")
    }
    let data = try Data(contentsOf: file, options: .mappedIfSafe)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let message = Data("Klik update v1\n\(version)\n\(file.lastPathComponent)\n\(digest)\n".utf8)
    let signature = try key.signature(for: message).base64EncodedString() + "\n"
    try signature.write(to: output, atomically: true, encoding: .utf8)
    print("Signed \(file.lastPathComponent)")
} else {
    fail("Usage: swift Scripts/update-signing.swift generate | public | sign vVERSION Klik-VERSION-arm64.dmg OUTPUT.sig")
}
