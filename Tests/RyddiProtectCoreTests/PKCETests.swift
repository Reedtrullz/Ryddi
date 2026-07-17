import Foundation
import XCTest
@testable import RyddiProtectCore

final class PKCETests: XCTestCase {
    private let redirectURI = URL(string: "ryddi://oauth/callback")!
    private let state = "state_0123456789abcdef0123456789"

    func testS256MatchesRFC7636AppendixBVector() throws {
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(PKCE.challengeMethod, "S256")
    }

    func testGeneratedPKCEUsesAValid256BitBase64URLVerifier() throws {
        let pkce = PKCE.generate()

        XCTAssertEqual(pkce.verifier.utf8.count, 43)
        XCTAssertTrue(pkce.verifier.utf8.allSatisfy(isUnreserved))
        XCTAssertFalse(pkce.verifier.contains("="))
        XCTAssertEqual(try PKCE(verifier: pkce.verifier).challenge, pkce.challenge)
        XCTAssertFalse(String(describing: pkce).contains(pkce.verifier))
    }

    func testVerifierValidationRejectsWrongLengthAndNonASCIIOrReservedCharacters() throws {
        XCTAssertThrowsError(try PKCE(verifier: String(repeating: "a", count: 42))) { error in
            XCTAssertEqual(error as? PKCEError, .invalidVerifierLength(actual: 42))
        }
        XCTAssertThrowsError(try PKCE(verifier: String(repeating: "a", count: 129))) { error in
            XCTAssertEqual(error as? PKCEError, .invalidVerifierLength(actual: 129))
        }
        for character in ["+", "/", "=", " ", "é"] {
            let verifier = String(repeating: "a", count: 42) + character
            XCTAssertThrowsError(try PKCE(verifier: verifier), character) { error in
                XCTAssertEqual(error as? PKCEError, .invalidVerifierCharacter)
            }
        }
    }

    func testGeneratedAuthorizationStateIsBoundedURLSafeAndRedacted() throws {
        let authorizationState = OAuthAuthorizationState.generate()

        XCTAssertEqual(authorizationState.value.utf8.count, 43)
        XCTAssertTrue(authorizationState.value.utf8.allSatisfy(isUnreserved))
        XCTAssertNoThrow(try OAuthAuthorizationState(authorizationState.value))
        XCTAssertFalse(String(describing: authorizationState).contains(authorizationState.value))
    }

    func testCallbackAcceptsOneExactStateAndOneNonemptyCode() throws {
        let callbackURL = callbackURL(items: [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code", value: "authorization-code"),
            URLQueryItem(name: "provider_extension", value: "allowed")
        ])

        let callback = try OAuthCallbackValidator.validate(
            callbackURL,
            expectedRedirectURI: redirectURI,
            expectedState: state
        )

        XCTAssertEqual(callback.withAuthorizationCode { $0 }, "authorization-code")
        XCTAssertFalse(String(describing: callback).contains("authorization-code"))
    }

    func testCallbackRejectsMissingDuplicateAndMismatchedState() throws {
        try assertCallbackError(
            items: [URLQueryItem(name: "code", value: "code")],
            expected: .missingState
        )
        try assertCallbackError(
            items: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code", value: "code")
            ],
            expected: .duplicateParameter("state")
        )
        try assertCallbackError(
            items: [
                URLQueryItem(name: "state", value: "state_9999999999999999999999999999"),
                URLQueryItem(name: "code", value: "code")
            ],
            expected: .stateMismatch
        )
    }

    func testStateIsValidatedBeforeProviderErrorIsSurfaced() throws {
        let callbackURL = callbackURL(items: [
            URLQueryItem(name: "state", value: "state_9999999999999999999999999999"),
            URLQueryItem(name: "error", value: "access_denied")
        ])

        XCTAssertThrowsError(
            try OAuthCallbackValidator.validate(
                callbackURL,
                expectedRedirectURI: redirectURI,
                expectedState: state
            )
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackValidationError, .stateMismatch)
        }
    }

    func testCallbackSurfacesAWellFormedProviderErrorAfterStateValidation() throws {
        let callbackURL = callbackURL(items: [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "error", value: "access_denied"),
            URLQueryItem(name: "error_description", value: "The user cancelled authorization."),
            URLQueryItem(name: "error_uri", value: "https://provider.example/errors/access_denied")
        ])

        XCTAssertThrowsError(
            try OAuthCallbackValidator.validate(
                callbackURL,
                expectedRedirectURI: redirectURI,
                expectedState: state
            )
        ) { error in
            XCTAssertEqual(
                error as? OAuthCallbackValidationError,
                .providerError(
                    code: "access_denied",
                    description: "The user cancelled authorization.",
                    errorURI: "https://provider.example/errors/access_denied"
                )
            )
        }
    }

    func testCallbackRejectsAmbiguousOrIncompleteCodeAndErrorResponses() throws {
        try assertCallbackError(
            items: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code", value: "code"),
                URLQueryItem(name: "error", value: "access_denied")
            ],
            expected: .codeAndError
        )
        try assertCallbackError(
            items: [URLQueryItem(name: "state", value: state)],
            expected: .missingCodeAndError
        )
        try assertCallbackError(
            items: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code", value: "one"),
                URLQueryItem(name: "code", value: "two")
            ],
            expected: .duplicateParameter("code")
        )
        try assertCallbackError(
            items: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code", value: "")
            ],
            expected: .emptyCode
        )
        try assertCallbackError(
            items: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "error_description", value: "orphaned")
            ],
            expected: .unexpectedErrorMetadata
        )
    }

    func testCallbackRequiresTheExactRedirectAndRejectsFragments() throws {
        let wrongRedirect = callbackURL(
            base: URL(string: "ryddi://oauth/other-callback")!,
            items: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code", value: "code")
            ]
        )
        XCTAssertThrowsError(
            try OAuthCallbackValidator.validate(
                wrongRedirect,
                expectedRedirectURI: redirectURI,
                expectedState: state
            )
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackValidationError, .unexpectedRedirectURI)
        }

        var fragmentComponents = URLComponents(url: callbackURL(items: [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code", value: "code")
        ]), resolvingAgainstBaseURL: false)!
        fragmentComponents.fragment = "code=fragment-code"
        let fragmentURL = fragmentComponents.url!
        XCTAssertThrowsError(
            try OAuthCallbackValidator.validate(
                fragmentURL,
                expectedRedirectURI: redirectURI,
                expectedState: state
            )
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackValidationError, .fragmentNotAllowed)
        }
    }

    func testPublicClientTokenRequestContainsOnlyTheExpectedExchangeParameters() throws {
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let callback = try OAuthCallbackValidator.validate(
            callbackURL(items: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code", value: "authorization-code")
            ]),
            expectedRedirectURI: redirectURI,
            expectedState: state
        )
        let request = try OAuthPublicClientTokenRequest(
            clientID: "public-client-id",
            callback: callback,
            redirectURI: redirectURI,
            pkce: pkce
        )

        let parameters = request.formParameters()
        XCTAssertEqual(
            Set(parameters.keys),
            Set(["grant_type", "client_id", "code", "redirect_uri", "code_verifier"])
        )
        XCTAssertEqual(parameters["grant_type"], "authorization_code")
        XCTAssertEqual(parameters["client_id"], "public-client-id")
        XCTAssertEqual(parameters["code"], "authorization-code")
        XCTAssertEqual(parameters["redirect_uri"], redirectURI.absoluteString)
        XCTAssertEqual(parameters["code_verifier"], pkce.verifier)
        XCTAssertNil(parameters["client_secret"])
        XCTAssertFalse(String(describing: request).contains("authorization-code"))
        XCTAssertFalse(String(describing: request).contains(pkce.verifier))
    }

    private func assertCallbackError(
        items: [URLQueryItem],
        expected: OAuthCallbackValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertThrowsError(
            try OAuthCallbackValidator.validate(
                callbackURL(items: items),
                expectedRedirectURI: redirectURI,
                expectedState: state
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackValidationError, expected, file: file, line: line)
        }
    }

    private func callbackURL(
        base: URL? = nil,
        items: [URLQueryItem]
    ) -> URL {
        var components = URLComponents(url: base ?? redirectURI, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        return components.url!
    }

    private func isUnreserved(_ byte: UInt8) -> Bool {
        switch byte {
        case 45, 46, 48...57, 65...90, 95, 97...122, 126:
            true
        default:
            false
        }
    }
}
