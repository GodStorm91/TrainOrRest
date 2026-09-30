import Foundation
import Security

struct ChatGPTJWK: Sendable, Equatable {
    let kid: String
    let modulus: String
    let exponent: String
    let keyType: String
    let algorithm: String?

    init(kid: String, modulus: String, exponent: String, keyType: String = "RSA", algorithm: String? = "RS256") {
        self.kid = kid
        self.modulus = modulus
        self.exponent = exponent
        self.keyType = keyType
        self.algorithm = algorithm
    }

    private enum CodingKeys: String, CodingKey {
        case kid, keyType = "kty", modulus = "n", exponent = "e", algorithm = "alg"
    }
}

extension ChatGPTJWK: Decodable {}

struct ChatGPTIDTokenClaims: Sendable, Equatable {
    let subject: String
    let email: String?
}

enum IDTokenValidationError: Error, Equatable {
    case malformedToken
    case unsupportedAlgorithm
    case keyNotFound
    case invalidSignature
    case invalidIssuer
    case invalidAudience
    case expired
    case invalidNonce
    case subjectMismatch
    case keyConstructionFailed
    case keyFetchFailed
}

protocol ChatGPTJWKSProviding: Sendable {
    func keys(forceRefresh: Bool) async throws -> [ChatGPTJWK]
}

protocol ChatGPTIDTokenValidating: Sendable {
    func validate(
        idToken: String,
        clientID: String,
        nonce: String,
        expectedSubject: String?
    ) async throws -> ChatGPTIDTokenClaims
}

actor ChatGPTJWKSProvider: ChatGPTJWKSProviding {
    private let session: URLSession
    private var cachedKeys: [ChatGPTJWK]?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func keys(forceRefresh: Bool) async throws -> [ChatGPTJWK] {
        if !forceRefresh, let cachedKeys {
            return cachedKeys
        }

        let (discoveryData, discoveryResponse) = try await session.data(from: ChatGPTAuthConfiguration.discoveryEndpoint)
        guard let discoveryHTTP = discoveryResponse as? HTTPURLResponse,
              (200..<300).contains(discoveryHTTP.statusCode),
              let discovery = try? JSONDecoder().decode(DiscoveryDocument.self, from: discoveryData),
              let jwksURL = URL(string: discovery.jwksURI) else {
            throw IDTokenValidationError.keyFetchFailed
        }

        let (jwksData, jwksResponse) = try await session.data(from: jwksURL)
        guard let jwksHTTP = jwksResponse as? HTTPURLResponse,
              (200..<300).contains(jwksHTTP.statusCode),
              let document = try? JSONDecoder().decode(JWKSDocument.self, from: jwksData) else {
            throw IDTokenValidationError.keyFetchFailed
        }

        cachedKeys = document.keys
        return document.keys
    }

    private struct DiscoveryDocument: Decodable {
        let jwksURI: String

        enum CodingKeys: String, CodingKey {
            case jwksURI = "jwks_uri"
        }
    }

    private struct JWKSDocument: Decodable {
        let keys: [ChatGPTJWK]
    }
}

final class IDTokenValidator: ChatGPTIDTokenValidating, @unchecked Sendable {
    private let keyProvider: any ChatGPTJWKSProviding
    private let now: @Sendable () -> Date

    init(
        keyProvider: any ChatGPTJWKSProviding = ChatGPTJWKSProvider(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keyProvider = keyProvider
        self.now = now
    }

    func validate(
        idToken: String,
        clientID: String,
        nonce: String,
        expectedSubject: String? = nil
    ) async throws -> ChatGPTIDTokenClaims {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = Data(base64URLEncoded: String(parts[0])),
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let signature = Data(base64URLEncoded: String(parts[2])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              header["alg"] as? String == "RS256",
              let kid = header["kid"] as? String else {
            throw IDTokenValidationError.malformedToken
        }

        var keys = try await keyProvider.keys(forceRefresh: false)
        var jwk = keys.first(where: { $0.kid == kid })
        if jwk == nil {
            keys = try await keyProvider.keys(forceRefresh: true)
            jwk = keys.first(where: { $0.kid == kid })
        }
        guard let jwk else { throw IDTokenValidationError.keyNotFound }
        guard jwk.keyType == "RSA", jwk.algorithm == nil || jwk.algorithm == "RS256" else {
            throw IDTokenValidationError.unsupportedAlgorithm
        }

        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        let publicKey = try Self.publicKey(for: jwk)
        var verificationError: Unmanaged<CFError>?
        guard SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData,
            signature as CFData,
            &verificationError
        ) else {
            throw IDTokenValidationError.invalidSignature
        }

        guard claims["iss"] as? String == ChatGPTAuthConfiguration.issuer else {
            throw IDTokenValidationError.invalidIssuer
        }
        guard Self.audiences(from: claims["aud"]).contains(clientID) else {
            throw IDTokenValidationError.invalidAudience
        }
        guard let expiry = (claims["exp"] as? NSNumber)?.doubleValue,
              expiry > now().addingTimeInterval(60).timeIntervalSince1970 else {
            throw IDTokenValidationError.expired
        }
        guard claims["nonce"] as? String == nonce else {
            throw IDTokenValidationError.invalidNonce
        }
        guard let subject = claims["sub"] as? String, !subject.isEmpty else {
            throw IDTokenValidationError.malformedToken
        }
        guard expectedSubject == nil || expectedSubject == subject else {
            throw IDTokenValidationError.subjectMismatch
        }

        return ChatGPTIDTokenClaims(subject: subject, email: claims["email"] as? String)
    }

    static func publicKey(for jwk: ChatGPTJWK) throws -> SecKey {
        guard let modulus = Data(base64URLEncoded: jwk.modulus), !modulus.isEmpty,
              let exponent = Data(base64URLEncoded: jwk.exponent), !exponent.isEmpty else {
            throw IDTokenValidationError.keyConstructionFailed
        }

        let der = rsaPublicKeyDER(modulus: modulus, exponent: exponent)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: modulus.count * 8
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw IDTokenValidationError.keyConstructionFailed
        }
        return key
    }

    private static func audiences(from value: Any?) -> [String] {
        if let audience = value as? String { return [audience] }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func rsaPublicKeyDER(modulus: Data, exponent: Data) -> Data {
        let body = derInteger(modulus) + derInteger(exponent)
        return Data([0x30]) + derLength(body.count) + body
    }

    private static func derInteger(_ value: Data) -> Data {
        var bytes = Array(value.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = [0] }
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return Data([0x02]) + derLength(bytes.count) + Data(bytes)
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var value = length
        var bytes = [UInt8]()
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var padded = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        self.init(base64Encoded: padded)
    }
}
