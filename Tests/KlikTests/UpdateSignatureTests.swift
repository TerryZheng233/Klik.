import CryptoKit
import XCTest
@testable import Klik

final class UpdateSignatureTests: XCTestCase {
    func testSignatureAuthenticatesVersionFilenameAndDigest() throws {
        let key = Curve25519.Signing.PrivateKey()
        let version = "v0.1.19"
        let filename = "Klik-0.1.19-arm64.dmg"
        let digest = String(repeating: "a", count: 64)
        let message = UpdateSignature.message(version: version, filename: filename, sha256: digest)
        let signed = Data((try key.signature(for: message).base64EncodedString() + "\n").utf8)
        let pub = key.publicKey.rawRepresentation
        XCTAssertTrue(UpdateSignature.verify(signature: signed, version: version, filename: filename, sha256: digest, publicKey: pub))
        XCTAssertFalse(UpdateSignature.verify(signature: signed, version: "v0.1.20", filename: filename, sha256: digest, publicKey: pub))
        XCTAssertFalse(UpdateSignature.verify(signature: signed, version: version, filename: "other.dmg", sha256: digest, publicKey: pub))
        XCTAssertFalse(UpdateSignature.verify(signature: signed, version: version, filename: filename, sha256: String(repeating: "b", count: 64), publicKey: pub))
        XCTAssertFalse(UpdateSignature.verify(signature: signed, version: version, filename: filename, sha256: digest, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation))
        XCTAssertFalse(UpdateSignature.verify(signature: Data("bad".utf8), version: version, filename: filename, sha256: digest, publicKey: pub))
    }
}
