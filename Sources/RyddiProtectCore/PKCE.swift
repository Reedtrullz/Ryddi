import CryptoKit
import Foundation

public enum PKCEError: Error, Equatable, Sendable {
    case invalidVerifierLength(actual: Int)
    case invalidVerifierCharacter
}

extension PKCEError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidVerifierLength(let actual):
            "A PKCE verifier must contain 43 through 128 ASCII characters; received \(actual)."
        case .invalidVerifierCharacter:
            "A PKCE verifier may contain only RFC 7636 unreserved ASCII characters."
        }
    }
}

/// RFC 7636 S256 proof material. It intentionally has no persistence conformance.
public struct PKCE: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let challengeMethod = "S256"

    private let verifierValue: String
    public let challenge: String

    public var verifier: String { verifierValue }

    public init(verifier: String) throws {
        let count = verifier.utf8.count
        guard (43...128).contains(count) else {
            throw PKCEError.invalidVerifierLength(actual: count)
        }
        guard verifier.utf8.allSatisfy(isRFC7636Unreserved) else {
            throw PKCEError.invalidVerifierCharacter
        }

        verifierValue = verifier
        challenge = Self.challenge(for: verifier)
    }

    public static func generate() -> PKCE {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(using generator: inout Generator) -> PKCE {
        let verifier = base64URLEncoded(randomBytes(count: 32, using: &generator))
        return PKCE(uncheckedVerifier: verifier)
    }

    public var description: String { "<redacted PKCE S256 material>" }
    public var debugDescription: String { description }

    private init(uncheckedVerifier verifier: String) {
        verifierValue = verifier
        challenge = Self.challenge(for: verifier)
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncoded(digest)
    }
}

public enum OAuthAuthorizationStateError: Error, Equatable, Sendable {
    case invalidValue
}

extension OAuthAuthorizationStateError: LocalizedError {
    public var errorDescription: String? {
        "OAuth state must contain 16 through 1,024 unreserved ASCII characters."
    }
}

/// A bounded, URL-safe anti-forgery state value. It intentionally has no persistence conformance.
public struct OAuthAuthorizationState: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    fileprivate let rawValue: String

    public var value: String { rawValue }

    public init(_ value: String) throws {
        guard (16...1_024).contains(value.utf8.count),
              value.utf8.allSatisfy(isRFC7636Unreserved) else {
            throw OAuthAuthorizationStateError.invalidValue
        }
        rawValue = value
    }

    public static func generate() -> OAuthAuthorizationState {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(
        using generator: inout Generator
    ) -> OAuthAuthorizationState {
        OAuthAuthorizationState(uncheckedValue: base64URLEncoded(randomBytes(count: 32, using: &generator)))
    }

    public var description: String { "<redacted OAuth authorization state>" }
    public var debugDescription: String { description }

    private init(uncheckedValue: String) {
        rawValue = uncheckedValue
    }
}

public struct OAuthAuthorizationCallback: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    fileprivate let authorizationCode: String

    public func withAuthorizationCode<Result>(_ body: (String) throws -> Result) rethrows -> Result {
        try body(authorizationCode)
    }

    public var description: String { "<validated OAuth authorization callback>" }
    public var debugDescription: String { description }
}

public enum OAuthCallbackValidationError: Error, Equatable, Sendable {
    case invalidExpectedState
    case invalidRedirectURI
    case unexpectedRedirectURI
    case fragmentNotAllowed
    case malformedQuery
    case missingState
    case duplicateParameter(String)
    case stateMismatch
    case codeAndError
    case missingCodeAndError
    case emptyCode
    case emptyError
    case invalidErrorMetadata(String)
    case unexpectedErrorMetadata
    case providerError(code: String, description: String?, errorURI: String?)
}

extension OAuthCallbackValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidExpectedState:
            "The expected OAuth state is invalid."
        case .invalidRedirectURI:
            "The OAuth redirect URI is invalid."
        case .unexpectedRedirectURI:
            "The OAuth callback does not match the expected redirect URI."
        case .fragmentNotAllowed:
            "OAuth callback parameters must not be returned in a URL fragment."
        case .malformedQuery:
            "The OAuth callback query could not be parsed."
        case .missingState:
            "The OAuth callback is missing its state value."
        case .duplicateParameter(let name):
            "The OAuth callback contains more than one \(name) parameter."
        case .stateMismatch:
            "The OAuth callback state does not match the authorization request."
        case .codeAndError:
            "The OAuth callback contains both an authorization code and an error."
        case .missingCodeAndError:
            "The OAuth callback contains neither an authorization code nor an error."
        case .emptyCode:
            "The OAuth callback contains an empty or invalid authorization code."
        case .emptyError:
            "The OAuth callback contains an empty or invalid error code."
        case .invalidErrorMetadata(let name):
            "The OAuth callback contains invalid \(name) metadata."
        case .unexpectedErrorMetadata:
            "The OAuth callback contains error metadata without an error."
        case .providerError(let code, let description, _):
            if let description {
                "The provider rejected authorization (\(code)): \(description)"
            } else {
                "The provider rejected authorization (\(code))."
            }
        }
    }
}

public enum OAuthCallbackValidator {
    public static func validate(
        _ callbackURL: URL,
        expectedRedirectURI: URL,
        expectedState: String
    ) throws -> OAuthAuthorizationCallback {
        let state: OAuthAuthorizationState
        do {
            state = try OAuthAuthorizationState(expectedState)
        } catch {
            throw OAuthCallbackValidationError.invalidExpectedState
        }
        return try validate(
            callbackURL,
            expectedRedirectURI: expectedRedirectURI,
            expectedState: state
        )
    }

    public static func validate(
        _ callbackURL: URL,
        expectedRedirectURI: URL,
        expectedState: OAuthAuthorizationState
    ) throws -> OAuthAuthorizationCallback {
        let expectedShape = try redirectShape(for: expectedRedirectURI, allowQuery: false)
        let callbackComponents = try callbackURLComponents(callbackURL)
        let callbackShape = try redirectShape(for: callbackURL, allowQuery: true)
        guard callbackShape == expectedShape else {
            throw OAuthCallbackValidationError.unexpectedRedirectURI
        }

        let queryItems: [URLQueryItem]
        if callbackComponents.percentEncodedQuery == nil {
            queryItems = []
        } else if let parsedItems = callbackComponents.queryItems {
            queryItems = parsedItems
        } else {
            throw OAuthCallbackValidationError.malformedQuery
        }

        let state = try singleValue(named: "state", in: queryItems)
        guard state.isPresent, let returnedState = state.value, !returnedState.isEmpty else {
            throw OAuthCallbackValidationError.missingState
        }
        guard constantTimeEqual(returnedState, expectedState.rawValue) else {
            throw OAuthCallbackValidationError.stateMismatch
        }

        let code = try singleValue(named: "code", in: queryItems)
        let error = try singleValue(named: "error", in: queryItems)
        let errorDescription = try singleValue(named: "error_description", in: queryItems)
        let errorURI = try singleValue(named: "error_uri", in: queryItems)

        guard !(code.isPresent && error.isPresent) else {
            throw OAuthCallbackValidationError.codeAndError
        }

        if error.isPresent {
            guard let errorCode = error.value,
                  isBoundedText(errorCode, maximumBytes: 256) else {
                throw OAuthCallbackValidationError.emptyError
            }
            let description = try validatedErrorMetadata(
                errorDescription,
                name: "error_description",
                maximumBytes: 4_096
            )
            let uri = try validatedErrorMetadata(errorURI, name: "error_uri", maximumBytes: 2_048)
            throw OAuthCallbackValidationError.providerError(
                code: errorCode,
                description: description,
                errorURI: uri
            )
        }

        guard !errorDescription.isPresent, !errorURI.isPresent else {
            throw OAuthCallbackValidationError.unexpectedErrorMetadata
        }
        guard code.isPresent else {
            throw OAuthCallbackValidationError.missingCodeAndError
        }
        guard let authorizationCode = code.value,
              isBoundedText(authorizationCode, maximumBytes: 8_192) else {
            throw OAuthCallbackValidationError.emptyCode
        }
        return OAuthAuthorizationCallback(authorizationCode: authorizationCode)
    }

    private static func callbackURLComponents(_ callbackURL: URL) throws -> URLComponents {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthCallbackValidationError.invalidRedirectURI
        }
        guard components.fragment == nil else {
            throw OAuthCallbackValidationError.fragmentNotAllowed
        }
        return components
    }

    private static func singleValue(
        named name: String,
        in items: [URLQueryItem]
    ) throws -> QueryParameter {
        let matches = items.filter { $0.name == name }
        guard matches.count <= 1 else {
            throw OAuthCallbackValidationError.duplicateParameter(name)
        }
        guard let match = matches.first else {
            return QueryParameter(isPresent: false, value: nil)
        }
        return QueryParameter(isPresent: true, value: match.value)
    }

    private static func validatedErrorMetadata(
        _ parameter: QueryParameter,
        name: String,
        maximumBytes: Int
    ) throws -> String? {
        guard parameter.isPresent else {
            return nil
        }
        guard let value = parameter.value,
              isBoundedText(value, maximumBytes: maximumBytes) else {
            throw OAuthCallbackValidationError.invalidErrorMetadata(name)
        }
        return value
    }
}

public enum OAuthPublicClientTokenRequestError: Error, Equatable, Sendable {
    case invalidClientID
    case invalidRedirectURI
}

extension OAuthPublicClientTokenRequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidClientID:
            "The OAuth public client identifier is invalid."
        case .invalidRedirectURI:
            "The OAuth token request redirect URI is invalid."
        }
    }
}

/// Parameters for an OAuth authorization-code exchange by a public client.
public struct OAuthPublicClientTokenRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let clientID: String
    public let redirectURI: URL

    private let authorizationCode: String
    private let codeVerifier: String

    public init(
        clientID: String,
        callback: OAuthAuthorizationCallback,
        redirectURI: URL,
        pkce: PKCE
    ) throws {
        guard isBoundedText(clientID, maximumBytes: 1_024) else {
            throw OAuthPublicClientTokenRequestError.invalidClientID
        }
        do {
            _ = try redirectShape(for: redirectURI, allowQuery: false)
        } catch {
            throw OAuthPublicClientTokenRequestError.invalidRedirectURI
        }

        self.clientID = clientID
        self.redirectURI = redirectURI
        authorizationCode = callback.authorizationCode
        codeVerifier = pkce.verifier
    }

    public func formParameters() -> [String: String] {
        [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": authorizationCode,
            "redirect_uri": redirectURI.absoluteString,
            "code_verifier": codeVerifier
        ]
    }

    public var description: String { "<redacted OAuth public-client token request>" }
    public var debugDescription: String { description }
}

private struct QueryParameter {
    let isPresent: Bool
    let value: String?
}

private struct RedirectShape: Equatable {
    let scheme: String
    let host: String?
    let port: Int?
    let percentEncodedPath: String
}

private func redirectShape(for url: URL, allowQuery: Bool) throws -> RedirectShape {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let scheme = components.scheme?.lowercased(),
          !scheme.isEmpty,
          components.user == nil,
          components.password == nil,
          components.fragment == nil,
          allowQuery || components.percentEncodedQuery == nil,
          !(components.host?.isEmpty ?? false),
          components.host != nil || !components.percentEncodedPath.isEmpty else {
        throw OAuthCallbackValidationError.invalidRedirectURI
    }

    return RedirectShape(
        scheme: scheme,
        host: components.host?.lowercased(),
        port: components.port,
        percentEncodedPath: components.percentEncodedPath
    )
}

private func isRFC7636Unreserved(_ byte: UInt8) -> Bool {
    switch byte {
    case 45, 46, 48...57, 65...90, 95, 97...122, 126:
        true
    default:
        false
    }
}

private func isBoundedText(_ value: String, maximumBytes: Int) -> Bool {
    !value.isEmpty
        && value.utf8.count <= maximumBytes
        && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

private func constantTimeEqual(_ left: String, _ right: String) -> Bool {
    let leftBytes = Array(left.utf8)
    let rightBytes = Array(right.utf8)
    let comparisonCount = max(leftBytes.count, rightBytes.count)
    var difference = leftBytes.count ^ rightBytes.count

    for index in 0..<comparisonCount {
        let leftByte = index < leftBytes.count ? leftBytes[index] : 0
        let rightByte = index < rightBytes.count ? rightBytes[index] : 0
        difference |= Int(leftByte ^ rightByte)
    }
    return difference == 0
}

private func randomBytes<Generator: RandomNumberGenerator>(
    count: Int,
    using generator: inout Generator
) -> [UInt8] {
    (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
}

private func base64URLEncoded<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
    Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
