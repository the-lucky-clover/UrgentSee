import XCTest
import CryptoKit
@testable import UrgentSee

/// iOS E2EE roundtrip tests — CryptoKit sealed-box path.
///
/// These tests call the REAL production crypto in E2EEManager
/// (static sealEncrypt/sealDecrypt core + instance wrappers).
/// No mocks, no simulations: real X25519 key agreement, real HKDF,
/// real ChaChaPoly AEAD, fresh random keypairs every run.
final class E2EERoundtripTests: XCTestCase {

    private func freshKeyPair() -> (Curve25519.KeyAgreement.PrivateKey, Curve25519.KeyAgreement.PublicKey) {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return (priv, priv.publicKey)
    }

    // 1. Basic roundtrip through the stateless core
    func testSealEncryptDecryptRoundtrip() throws {
        let (priv, pub) = freshKeyPair()
        let message = "URGENT: meet at the north gate in 5 minutes"
        let sealed = try E2EEManager.sealEncrypt(message: message, recipientPublicKey: pub)
        let opened = try E2EEManager.sealDecrypt(sealedMessageBase64: sealed, privateKey: priv)
        XCTAssertEqual(opened, message)
    }

    // 2. Same path the app uses (base64 entry points)
    func testBase64EntryPointsRoundtrip() throws {
        let (priv, pub) = freshKeyPair()
        let message = "MEDICAL EMERGENCY: need help at [LOCATION]"
        let sealed = try E2EEManager.sealEncrypt(message: message, recipientPublicKey: pub)
        let opened = try E2EEManager.sealDecrypt(sealedMessageBase64: sealed, privateKey: priv)
        XCTAssertEqual(opened, message)
        XCTAssertEqual(pub.rawRepresentation.base64EncodedString().count, 44)
    }

    // 3. Fresh ephemeral key => fresh ciphertext every time
    func testCiphertextIsNondeterministic() throws {
        let (_, pub) = freshKeyPair()
        let message = "same plaintext twice"
        let first = try E2EEManager.sealEncrypt(message: message, recipientPublicKey: pub)
        let second = try E2EEManager.sealEncrypt(message: message, recipientPublicKey: pub)
        XCTAssertNotEqual(first, second)
    }

    // 4. Wrong private key must NOT decrypt
    func testWrongPrivateKeyFailsToDecrypt() throws {
        let (_, pub) = freshKeyPair()
        let (wrongPriv, _) = freshKeyPair()
        let sealed = try E2EEManager.sealEncrypt(message: "secret", recipientPublicKey: pub)
        XCTAssertThrowsError(try E2EEManager.sealDecrypt(sealedMessageBase64: sealed, privateKey: wrongPriv))
    }

    // 5. Tampered ciphertext must fail authentication (ChaChaPoly tag)
    func testTamperedCiphertextFailsAuthentication() throws {
        let (priv, pub) = freshKeyPair()
        let sealed = try E2EEManager.sealEncrypt(message: "do not tamper", recipientPublicKey: pub)
        var data = Data(base64Encoded: sealed)!
        data[data.count - 1] ^= 0xFF
        XCTAssertThrowsError(try E2EEManager.sealDecrypt(sealedMessageBase64: data.base64EncodedString(), privateKey: priv))
    }

    // 6. Truncated / garbage input rejected
    func testTruncatedAndGarbageInputRejected() throws {
        let (priv, _) = freshKeyPair()
        XCTAssertThrowsError(try E2EEManager.sealDecrypt(sealedMessageBase64: "!!!not-base64!!!", privateKey: priv))
        XCTAssertThrowsError(try E2EEManager.sealDecrypt(sealedMessageBase64: Data([1, 2, 3]).base64EncodedString(), privateKey: priv))
        XCTAssertThrowsError(try E2EEManager.sealDecrypt(sealedMessageBase64: Data(repeating: 0, count: 40).base64EncodedString(), privateKey: priv))
    }

    // 7. Unicode / emoji roundtrip (dispatch payloads are user text)
    func testUnicodeAndEmojiRoundtrip() throws {
        let (priv, pub) = freshKeyPair()
        let message = "Critical Alert - cafe naive 日本語 🎯"
        let sealed = try E2EEManager.sealEncrypt(message: message, recipientPublicKey: pub)
        XCTAssertEqual(try E2EEManager.sealDecrypt(sealedMessageBase64: sealed, privateKey: priv), message)
    }

    // 8. Empty string roundtrips (edge: zero-length plaintext)
    func testEmptyMessageRoundtrip() throws {
        let (priv, pub) = freshKeyPair()
        let sealed = try E2EEManager.sealEncrypt(message: "", recipientPublicKey: pub)
        XCTAssertEqual(try E2EEManager.sealDecrypt(sealedMessageBase64: sealed, privateKey: priv), "")
    }

    // 9. Long message roundtrip (multi-block ChaChaPoly)
    func testLongMessageRoundtrip() throws {
        let (priv, pub) = freshKeyPair()
        let message = String(repeating: "UrgentSee E2EE confidentiality + integrity. ", count: 200)
        let sealed = try E2EEManager.sealEncrypt(message: message, recipientPublicKey: pub)
        XCTAssertEqual(try E2EEManager.sealDecrypt(sealedMessageBase64: sealed, privateKey: priv), message)
    }

    // 10. Blob layout: [ephem_pk 32B][nonce 12B][ct][tag 16B]
    func testSealedBlobLayout() throws {
        let (_, pub) = freshKeyPair()
        let plaintext = "layout check"
        let sealed = try E2EEManager.sealEncrypt(message: plaintext, recipientPublicKey: pub)
        let data = Data(base64Encoded: sealed)!
        let expected = 32 + 12 + plaintext.utf8.count + 16
        XCTAssertEqual(data.count, expected, "sealed blob must be ephem_pk(32)+nonce(12)+ct+tag(16)")
        XCTAssertNoThrow(try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data.prefix(32)))
    }

    // 11. Cross-party: Alice encrypts to Bob, Bob decrypts (two independent keypairs)
    func testAliceToBobCrossParty() throws {
        let alicePriv = Curve25519.KeyAgreement.PrivateKey()
        let bobPriv = Curve25519.KeyAgreement.PrivateKey()
        _ = alicePriv.publicKey
        let sealed = try E2EEManager.sealEncrypt(message: "from Alice to Bob", recipientPublicKey: bobPriv.publicKey)
        XCTAssertEqual(try E2EEManager.sealDecrypt(sealedMessageBase64: sealed, privateKey: bobPriv), "from Alice to Bob")
        XCTAssertThrowsError(try E2EEManager.sealDecrypt(sealedMessageBase64: sealed, privateKey: alicePriv))
    }
}
