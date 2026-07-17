import Foundation
import XCTest
@testable import RyddiProtectCore

final class ProtectionRuleProposalTests: XCTestCase {
    func testProposalIsAdditiveProtectOnlyAndRequiresConfirmation() throws {
        let subject = try makeSubject()
        let proposal = try ProtectionRuleProposal(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            subject: subject,
            localPath: "/Users/example/Cloud/../Cloud/Documents",
            reason: .localCloudRoot,
            includeDescendants: true,
            proposedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(proposal.subject, subject)
        XCTAssertEqual(proposal.localPath, "/Users/example/Cloud/Documents")
        XCTAssertEqual(proposal.reason, .localCloudRoot)
        XCTAssertTrue(proposal.includeDescendants)
        XCTAssertEqual(proposal.proposedKind, .protect)
        XCTAssertTrue(proposal.isAdditiveOnly)
        XCTAssertTrue(proposal.requiresExplicitConfirmation)
    }

    func testProposalRejectsRelativeRootControlAndOversizedPaths() throws {
        let subject = try makeSubject()
        for invalidPath in [
            "relative/path",
            "/",
            "/Users/example/unsafe\npath",
            "/" + String(repeating: "a", count: ProtectionRuleProposal.maximumPathBytes)
        ] {
            XCTAssertThrowsError(try ProtectionRuleProposal(
                subject: subject,
                localPath: invalidPath,
                reason: .userSelectedProtection
            )) { error in
                XCTAssertEqual(error as? ProtectionRuleProposalError, .invalidLocalPath)
            }
        }
    }

    func testProposalCarriesNoReplacementOrExclusionState() throws {
        let proposal = try ProtectionRuleProposal(
            subject: makeSubject(),
            localPath: "/Users/example/Cloud",
            reason: .userSelectedProtection
        )

        XCTAssertEqual(
            Set(Mirror(reflecting: proposal).children.compactMap(\.label)),
            ["id", "includeDescendants", "localPath", "proposedAt", "reason", "subject"]
        )
    }

    private func makeSubject() throws -> ProtectionSubject {
        try ProtectionSubject(
            scanSessionID: "scan-session",
            findingID: "finding-id",
            filesystemIdentity: ProtectionFilesystemIdentity(
                fileResourceIdentifier: "file-2",
                volumeIdentifier: "volume-1",
                isDirectory: true,
                isRegularFile: false,
                isSymbolicLink: false,
                isPackage: false,
                isVolume: false,
                fileSize: nil,
                allocatedSize: nil,
                modificationDate: Date(timeIntervalSince1970: 50)
            )
        )
    }
}
