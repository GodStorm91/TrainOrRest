import Foundation
import Security
import XCTest
@testable import TrainOrRest

final class IDTokenValidatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testValidTokenPasses() async throws {
        let fixture = try JWTFixture()
        let validator = IDTokenValidator(keyProvider: StaticJWKSProvider(keys: [fixture.jwk]), now: { self.now })
        let token = try fixture.token(claims: claims())

        let result = try await validator.validate(
            idToken: token,
            clientID: "oaiapp_test",
            nonce: "nonce-1",
            expectedSubject: nil
        )

        XCTAssertEqual(result, ChatGPTIDTokenClaims(subject: "subject-1", email: "runner@example.com"))
    }

    func testBadSignatureIsRejected() async throws {
        let fixture = try JWTFixture()
        let validator = IDTokenValidator(keyProvider: StaticJWKSProvider(keys: [fixture.jwk]), now: { self.now })
        var token = try fixture.token(claims: claims())
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        var signature = String(parts[2])
        signature.replaceSubrange(signature.startIndex...signature.startIndex, with: signature.first == "A" ? "B" : "A")
        token = "\(parts[0]).\(parts[1]).\(signature)"

        await assertValidationFails(validator, token: token)
    }

    func testWrongAudienceIsRejected() async throws {
        let fixture = try JWTFixture()
        let validator = IDTokenValidator(keyProvider: StaticJWKSProvider(keys: [fixture.jwk]), now: { self.now })
        var wrongAudienceClaims = claims()
        wrongAudienceClaims["aud"] = "oaiapp_other"

        await assertValidationFails(validator, token: try fixture.token(claims: wrongAudienceClaims))
    }

    func testExpiredTokenIsRejected() async throws {
        let fixture = try JWTFixture()
        let validator = IDTokenValidator(keyProvider: StaticJWKSProvider(keys: [fixture.jwk]), now: { self.now })
        var expiredClaims = claims()
        expiredClaims["exp"] = now.addingTimeInterval(-1).timeIntervalSince1970

        await assertValidationFails(validator, token: try fixture.token(claims: expiredClaims))
    }

    func testWrongNonceIsRejected() async throws {
        let fixture = try JWTFixture()
        let validator = IDTokenValidator(keyProvider: StaticJWKSProvider(keys: [fixture.jwk]), now: { self.now })
        var wrongNonceClaims = claims()
        wrongNonceClaims["nonce"] = "wrong-nonce"

        await assertValidationFails(validator, token: try fixture.token(claims: wrongNonceClaims))
    }

    func testSubjectMismatchIsRejected() async throws {
        let fixture = try JWTFixture()
        let validator = IDTokenValidator(keyProvider: StaticJWKSProvider(keys: [fixture.jwk]), now: { self.now })
        let token = try fixture.token(claims: claims())

        do {
            _ = try await validator.validate(
                idToken: token,
                clientID: "oaiapp_test",
                nonce: "nonce-1",
                expectedSubject: "other-subject"
            )
            XCTFail("Expected a subject mismatch")
        } catch let error as IDTokenValidationError {
            XCTAssertEqual(error, .subjectMismatch)
        }
    }

    private func claims() -> [String: Any] {
        [
            "iss": ChatGPTAuthConfiguration.issuer,
            "aud": ["oaiapp_test", "other-audience"],
            "exp": now.addingTimeInterval(3_600).timeIntervalSince1970,
            "nonce": "nonce-1",
            "sub": "subject-1",
            "email": "runner@example.com"
        ]
    }

    private func assertValidationFails(_ validator: IDTokenValidator, token: String) async {
        do {
            _ = try await validator.validate(
                idToken: token,
                clientID: "oaiapp_test",
                nonce: "nonce-1",
                expectedSubject: nil
            )
            XCTFail("Expected ID-token validation to fail")
        } catch {
            // The specific invalid claim is covered by the test name.
        }
    }
}

private actor StaticJWKSProvider: ChatGPTJWKSProviding {
    private let storedKeys: [ChatGPTJWK]

    init(keys: [ChatGPTJWK]) {
        storedKeys = keys
    }

    func keys(forceRefresh: Bool) async throws -> [ChatGPTJWK] {
        storedKeys
    }
}

private struct JWTFixture {
    let privateKey: SecKey
    let jwk: ChatGPTJWK

    init() throws {
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2_048,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let representation = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw IDTokenValidationError.keyConstructionFailed
        }

        self.privateKey = privateKey
        let values = try Self.rsaValues(from: representation)
        jwk = ChatGPTJWK(
            kid: "test-key",
            modulus: Data(values.modulus.drop(while: { $0 == 0 })).base64URLEncodedString(),
            exponent: Data(values.exponent.drop(while: { $0 == 0 })).base64URLEncodedString()
        )
    }

    func token(claims: [String: Any]) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": jwk.kid], options: [.sortedKeys])
        let payload = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        let signingInput = "\(header.base64URLEncodedString()).\(payload.base64URLEncodedString())"

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &error
        ) as Data? else {
            throw IDTokenValidationError.invalidSignature
        }
        return "\(signingInput).\(signature.base64URLEncodedString())"
    }

    private static func rsaValues(from representation: Data) throws -> (modulus: [UInt8], exponent: [UInt8]) {
        var root = DERReader(Array(representation))
        guard let outer = root.element(), outer.tag == 0x30 else {
            throw IDTokenValidationError.keyConstructionFailed
        }

        var body = outer.value
        var reader = DERReader(body)
        guard let first = reader.element() else { throw IDTokenValidationError.keyConstructionFailed }
        if first.tag == 0x30 {
            guard let bitString = reader.element(), bitString.tag == 0x03, bitString.value.first == 0 else {
                throw IDTokenValidationError.keyConstructionFailed
            }
            var keyReader = DERReader(Array(bitString.value.dropFirst()))
            guard let keySequence = keyReader.element(), keySequence.tag == 0x30 else {
                throw IDTokenValidationError.keyConstructionFailed
            }
            body = keySequence.value
        }

        var keyBody = DERReader(body)
        guard let modulus = keyBody.element(), modulus.tag == 0x02,
              let exponent = keyBody.element(), exponent.tag == 0x02 else {
            throw IDTokenValidationError.keyConstructionFailed
        }
        return (modulus.value, exponent.value)
    }
}

private struct DERReader {
    private var bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func element() -> (tag: UInt8, value: [UInt8])? {
        guard index < bytes.count else { return nil }
        let tag = bytes[index]
        index += 1
        guard let length = readLength(), index + length <= bytes.count else { return nil }
        let value = Array(bytes[index..<(index + length)])
        index += length
        return (tag, value)
    }

    private mutating func readLength() -> Int? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        index += 1
        if first & 0x80 == 0 { return Int(first) }
        let count = Int(first & 0x7f)
        guard count > 0, index + count <= bytes.count else { return nil }
        var value = 0
        for _ in 0..<count {
            value = (value << 8) | Int(bytes[index])
            index += 1
        }
        return value
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
