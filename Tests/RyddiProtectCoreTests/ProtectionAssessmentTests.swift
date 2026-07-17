import Foundation
import XCTest
@testable import RyddiProtectCore

final class ProtectionAssessmentTests: XCTestCase {
    func testAssessmentBindsToScanFindingAndFilesystemIdentity() throws {
        let identity = fixtureIdentity(size: 42)
        let subject = try ProtectionSubject(
            scanSessionID: "scan-1",
            findingID: "finding-1",
            filesystemIdentity: identity
        )
        let assessment = try ProtectionAssessment(
            subject: subject,
            source: .userSelectedCloudObject,
            state: .providerEvidenceObserved,
            reasons: [.contentIdentityMatched]
        )

        XCTAssertEqual(assessment.subject.scanSessionID, "scan-1")
        XCTAssertEqual(assessment.subject.findingID, "finding-1")
        XCTAssertEqual(assessment.subject.filesystemIdentity, identity)
        XCTAssertTrue(assessment.isAdvisoryOnly)
    }

    func testEveryStateRequiresTypedEvidenceReason() throws {
        let subject = try ProtectionSubject(
            scanSessionID: "scan-1",
            findingID: "finding-1",
            filesystemIdentity: fixtureIdentity(size: 1)
        )

        for state in ProtectionAssessmentState.allCases {
            XCTAssertThrowsError(try ProtectionAssessment(
                subject: subject,
                source: .unknown,
                state: state,
                reasons: []
            )) { error in
                XCTAssertEqual(error as? ProtectionAssessmentError, .missingRequiredReason)
            }
        }
    }

    func testSubjectRejectsEmptyAndControlCharacterIdentifiers() {
        XCTAssertThrowsError(try ProtectionSubject(
            scanSessionID: "",
            findingID: "finding-1",
            filesystemIdentity: fixtureIdentity(size: 1)
        ))
        XCTAssertThrowsError(try ProtectionSubject(
            scanSessionID: "scan-1",
            findingID: "finding\n1",
            filesystemIdentity: fixtureIdentity(size: 1)
        ))
    }

    func testAssessmentSurfaceHasNoCleanupAuthorityOrRawPath() throws {
        let subject = try ProtectionSubject(
            scanSessionID: "scan-1",
            findingID: "finding-1",
            filesystemIdentity: fixtureIdentity(size: 1)
        )
        let assessment = try ProtectionAssessment(
            subject: subject,
            source: .secretSourceMetadata,
            state: .requiresProtection,
            reasons: [.secretSource, .userDecisionRequired]
        )

        let fieldNames = Set(Mirror(reflecting: assessment).children.compactMap(\.label))
        XCTAssertEqual(fieldNames, ["assessedAt", "id", "reasons", "source", "state", "subject"])
        XCTAssertFalse(fieldNames.contains("path"))
        XCTAssertFalse(fieldNames.contains("authorization"))
        XCTAssertFalse(fieldNames.contains("cleanupEligible"))
    }

    private func fixtureIdentity(size: Int64) -> ProtectionFilesystemIdentity {
        ProtectionFilesystemIdentity(
            fileResourceIdentifier: "resource-1",
            volumeIdentifier: "volume-1",
            isDirectory: false,
            isRegularFile: true,
            isSymbolicLink: false,
            isPackage: false,
            isVolume: false,
            fileSize: size,
            allocatedSize: size,
            modificationDate: Date(timeIntervalSince1970: 100)
        )
    }
}
