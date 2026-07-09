import XCTest
@testable import ReclaimerCore

final class ScanSessionCompatibilityTests: XCTestCase {
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testOldSessionWithoutInvalidationReasonsDecodesAsInvalidatedWhenDigestMissing() throws {
        let json = """
        {
          "id": "session-old",
          "createdAt": "2026-07-09T00:00:00Z",
          "updatedAt": "2026-07-09T00:00:00Z",
          "appVersion": "0.2.0",
          "ruleVersion": "2026-07-08",
          "preset": "developer",
          "scopeDigest": "scope",
          "stage": "scanned"
        }
        """.data(using: .utf8)!

        let session = try makeDecoder().decode(ScanSession.self, from: json)

        XCTAssertEqual(session.stage, .invalidated)
        XCTAssertEqual(session.invalidationReasons, [.findingsChanged])
    }

    func testDigestIsStableAcrossInputOrdering() {
        let first = ScanSessionDigestBuilder.digest(.init(
            appVersion: "0.3.0",
            ruleVersion: "rules-a",
            preset: .developer,
            roots: ["/b", "/a"],
            userPolicyDigest: "policy",
            findingIDs: ["2", "1"],
            actionKinds: ["trash", "deleteCache"],
            pathMetadata: ["b": "inode-2", "a": "inode-1"],
            selectedPlanIDs: ["plan-b", "plan-a"]
        ))

        let second = ScanSessionDigestBuilder.digest(.init(
            appVersion: "0.3.0",
            ruleVersion: "rules-a",
            preset: .developer,
            roots: ["/a", "/b"],
            userPolicyDigest: "policy",
            findingIDs: ["1", "2"],
            actionKinds: ["deleteCache", "trash"],
            pathMetadata: ["a": "inode-1", "b": "inode-2"],
            selectedPlanIDs: ["plan-a", "plan-b"]
        ))

        XCTAssertEqual(first, second)
    }
}
