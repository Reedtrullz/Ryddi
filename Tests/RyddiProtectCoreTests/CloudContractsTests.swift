import XCTest
@testable import RyddiProtectCore

final class CloudContractsTests: XCTestCase {
    func testConnectionReferenceUsesNeutralLabelWithoutProviderAccountIdentity() throws {
        let reference = try CloudConnectionReference(
            provider: .dropbox,
            ordinal: 2,
            connectedAt: Date(timeIntervalSince1970: 100),
            grantedCapabilities: [.readMetadata, .userSelectedFiles]
        )

        XCTAssertEqual(reference.displayLabel, "Dropbox 2")
        XCTAssertEqual(
            Set(Mirror(reflecting: reference).children.compactMap(\.label)),
            ["connectedAt", "grantedCapabilities", "id", "ordinal", "provider"]
        )
    }

    func testConnectionReferenceRejectsInvalidOrdinal() {
        XCTAssertThrowsError(try CloudConnectionReference(
            provider: .googleDrive,
            ordinal: 0,
            grantedCapabilities: [.userSelectedFiles]
        )) { error in
            XCTAssertEqual(error as? CloudContractError, .invalidConnectionOrdinal)
        }
    }

    func testConnectionLocatorRoundTripsWithoutAccountIdentity() throws {
        let locator = try CloudConnectionLocator(
            id: UUID(uuidString: "7818380F-2805-49A0-9557-B17BFB26E221")!,
            provider: .googleDrive,
            ordinal: 4
        )

        let decoded = try JSONDecoder().decode(
            CloudConnectionLocator.self,
            from: JSONEncoder().encode(locator)
        )

        XCTAssertEqual(decoded, locator)
        XCTAssertEqual(
            Set(Mirror(reflecting: decoded).children.compactMap(\.label)),
            ["id", "ordinal", "provider"]
        )
    }

    func testCloudObjectRejectsControlCharactersNegativeSizesAndOversizedPages() throws {
        XCTAssertThrowsError(try CloudObjectReference(
            id: "object-1",
            provider: .mega,
            displayName: "unsafe\nname",
            objectKind: .file
        ))
        XCTAssertThrowsError(try CloudObjectReference(
            id: "object-1",
            provider: .mega,
            displayName: "file",
            objectKind: .file,
            logicalBytes: -1
        ))

        let item = try CloudObjectReference(
            id: "object-1",
            provider: .mega,
            displayName: "file",
            objectKind: .file,
            logicalBytes: 1
        )
        XCTAssertThrowsError(try CloudInventoryPage(
            objects: Array(repeating: item, count: CloudInventoryLimits.maximumPageObjects + 1),
            nextCursor: nil,
            truncated: false,
            responseByteCount: 100
        ))
    }

    func testCloudObjectRejectsTraversalAndInvalidOptionalMetadata() {
        for name in ["..", "../escape", "/absolute", "\\absolute", "folder/../escape", "folder\\..\\escape"] {
            XCTAssertThrowsError(try CloudObjectReference(
                id: "object-1",
                provider: .dropbox,
                displayName: name,
                objectKind: .file
            ))
        }
        XCTAssertThrowsError(try CloudObjectReference(
            id: "object-1",
            provider: .dropbox,
            displayName: "safe name",
            objectKind: .file,
            revision: "unsafe\nrevision"
        ))
    }

    func testCloudPageRejectsOversizedResponseByteCount() throws {
        let item = try CloudObjectReference(
            id: "object-1",
            provider: .dropbox,
            displayName: "safe name",
            objectKind: .file
        )

        XCTAssertThrowsError(try CloudInventoryPage(
            objects: [item],
            nextCursor: nil,
            truncated: false,
            responseByteCount: CloudInventoryLimits.maximumResponseBytes + 1
        )) { error in
            XCTAssertEqual(error as? CloudContractError, .invalidResponseSize)
        }
    }

    func testCloudPageNeverAccountsLessThanCanonicalMetadataBytes() throws {
        let item = try CloudObjectReference(
            id: "object-1",
            provider: .dropbox,
            displayName: "safe name",
            objectKind: .file,
            revision: "revision-1"
        )

        let page = try CloudInventoryPage(
            objects: [item],
            nextCursor: "cursor-1",
            truncated: false,
            responseByteCount: 0
        )

        XCTAssertEqual(page.rawResponseByteCount, 0)
        XCTAssertGreaterThan(page.responseByteCount, 0)
    }

    func testCanonicalMetadataBoundRejectsUnderreportedOversizedPage() throws {
        let item = try CloudObjectReference(
            id: String(repeating: "i", count: 2_048),
            provider: .dropbox,
            displayName: String(repeating: "n", count: 4_096),
            objectKind: .file
        )

        XCTAssertThrowsError(try CloudInventoryPage(
            objects: Array(repeating: item, count: CloudInventoryLimits.maximumPageObjects),
            nextCursor: nil,
            truncated: false,
            responseByteCount: 0
        )) { error in
            XCTAssertEqual(error as? CloudContractError, .invalidResponseSize)
        }
    }

    func testReadinessNonClaimsDoNotPromiseBackupOrCleanup() {
        let text = (ProtectReadinessNonClaims.cloud + ProtectReadinessNonClaims.secrets).joined(separator: " ")
        XCTAssertTrue(text.contains("No local or remote file was deleted"))
        XCTAssertTrue(text.contains("No file was uploaded"))
        XCTAssertTrue(text.contains("No secret value was migrated"))
        XCTAssertTrue(text.contains("No source file was changed"))
    }
}
