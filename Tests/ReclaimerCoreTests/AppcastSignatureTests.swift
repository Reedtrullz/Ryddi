import CryptoKit
import XCTest

final class AppcastSignatureTests: XCTestCase {
    func testBootstrapAppcastHasValidEd25519SignedFeedSignature() throws {
        let data = try Data(contentsOf: repoRoot().appendingPathComponent("appcast.xml"))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let signature = try capture(#"edSignature: ([A-Za-z0-9+/=]+)"#, in: text)
        let signedLength = try XCTUnwrap(Int(try capture(#"length: ([0-9]+)"#, in: text)))
        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: XCTUnwrap(Data(base64Encoded: "4YdSipywmXBBwUau2EfbDEcHTuvbJKxTkJATpH0gnnU="))
        )

        XCTAssertTrue(
            publicKey.isValidSignature(
                try XCTUnwrap(Data(base64Encoded: signature)),
                for: data.prefix(signedLength)
            )
        )
        XCTAssertTrue(text.contains("<title>Ryddi</title>"))
        XCTAssertFalse(text.contains("<item>"), "The bootstrap feed must not advertise an unavailable update.")
    }

    private func capture(_ pattern: String, in text: String) throws -> String {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = try XCTUnwrap(expression.firstMatch(in: text, range: range))
        let swiftRange = try XCTUnwrap(Range(match.range(at: 1), in: text))
        return String(text[swiftRange])
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
