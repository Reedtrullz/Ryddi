import Foundation
import XCTest
@testable import ReclaimerCore

final class StorageAccountingTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiStorageAccountingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testEstimatedAccountingUsesConservativeAllocatedAndLogicalFloor() {
        let equal = StorageAccounting(
            logicalBytes: 100,
            allocatedBytes: 100,
            status: .estimated
        )
        let sparseStyle = StorageAccounting(
            logicalBytes: 1_000,
            allocatedBytes: 100,
            status: .estimated
        )
        let blockAndMetadataStyle = StorageAccounting(
            logicalBytes: 100,
            allocatedBytes: 1_000,
            status: .estimated
        )

        XCTAssertEqual(equal.estimatedImmediateReclaimBytes, 100)
        XCTAssertEqual(sparseStyle.estimatedImmediateReclaimBytes, 100)
        XCTAssertEqual(blockAndMetadataStyle.estimatedImmediateReclaimBytes, 100)
    }

    func testUnknownAndSharedCloneAccountingNeverPromisesImmediateReclaim() {
        let unknown = StorageAccounting(
            logicalBytes: 1_000,
            allocatedBytes: 900,
            status: .unknown,
            physicalReclaimBytes: 900
        )
        let sharedClone = StorageAccounting(
            logicalBytes: 1_000,
            allocatedBytes: 900,
            status: .sharedCloneBacked,
            physicalReclaimBytes: 900
        )

        XCTAssertEqual(unknown.estimatedImmediateReclaimBytes, 0)
        XCTAssertEqual(sharedClone.estimatedImmediateReclaimBytes, 0)
    }

    func testObservedDeltaOnlyReportsPositiveFreeSpaceIncrease() {
        let observed = StorageAccounting(
            logicalBytes: 1_000,
            allocatedBytes: 900,
            status: .observedDelta,
            physicalReclaimBytes: 350
        )

        XCTAssertEqual(observed.estimatedImmediateReclaimBytes, 350)
        XCTAssertEqual(StorageAccounting.observedReclaimBytes(beforeFreeBytes: 100, afterFreeBytes: 450), 350)
        XCTAssertNil(StorageAccounting.observedReclaimBytes(beforeFreeBytes: 450, afterFreeBytes: 100))
        XCTAssertNil(StorageAccounting.observedReclaimBytes(beforeFreeBytes: 100, afterFreeBytes: 100))
        XCTAssertNil(StorageAccounting.observedReclaimBytes(beforeFreeBytes: nil, afterFreeBytes: 100))
    }

    func testLegacyFindingDecodingSynthesizesConservativeAccounting() throws {
        let data = Data(
            """
            {
              "id": "legacy-finding",
              "scopeName": "Fixture",
              "path": "/tmp/legacy-cache",
              "displayName": "legacy-cache",
              "logicalSize": 1000,
              "allocatedSize": 100,
              "isDirectory": false,
              "isSymbolicLink": false,
              "safetyClass": "autoSafe",
              "actionKind": "deleteCache",
              "ruleMatches": [],
              "evidence": []
            }
            """.utf8
        )

        let finding = try JSONDecoder().decode(Finding.self, from: data)

        XCTAssertEqual(finding.storageAccounting?.status, .estimated)
        XCTAssertEqual(finding.storageAccounting?.estimatedImmediateReclaimBytes, 100)
        XCTAssertNil(finding.measurementCoverage)
        XCTAssertTrue(finding.storageAccountingNote.localizedCaseInsensitiveContains("estimate"))
    }

    func testFilesystemIdentityCapturesSharedHardLinkIdentityForRegularFiles() throws {
        let original = tempRoot.appendingPathComponent("original.bin")
        let sibling = tempRoot.appendingPathComponent("sibling.bin")
        try Data(repeating: 0x41, count: 32).write(to: original)
        try FileManager.default.linkItem(at: original, to: sibling)

        let originalIdentity = try FilesystemIdentity.capture(at: original)
        let siblingIdentity = try FilesystemIdentity.capture(at: sibling)

        XCTAssertTrue(originalIdentity.isRegularFile)
        XCTAssertTrue(siblingIdentity.isRegularFile)
        XCTAssertGreaterThanOrEqual(originalIdentity.hardLinkCount ?? 0, 2)
        XCTAssertEqual(originalIdentity.fileIdentityKey, siblingIdentity.fileIdentityKey)
        XCTAssertNotNil(originalIdentity.fileIdentityKey)
    }

    func testFilesystemIdentityDoesNotAssignHardLinkIdentityToDirectoryOrSymlink() throws {
        let directory = tempRoot.appendingPathComponent("directory", isDirectory: true)
        let target = tempRoot.appendingPathComponent("target.txt")
        let symlink = tempRoot.appendingPathComponent("target-link")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        let directoryIdentity = try FilesystemIdentity.capture(at: directory)
        let symlinkIdentity = try FilesystemIdentity.capture(at: symlink)

        XCTAssertNil(directoryIdentity.hardLinkCount)
        XCTAssertNil(directoryIdentity.fileIdentityKey)
        XCTAssertTrue(symlinkIdentity.isSymbolicLink)
        XCTAssertNil(symlinkIdentity.hardLinkCount)
        XCTAssertNil(symlinkIdentity.fileIdentityKey)
    }

    func testLegacyFilesystemIdentityDecodingLeavesNewFieldsNil() throws {
        let data = Data(
            """
            {
              "fileResourceIdentifier": "data:file",
              "volumeIdentifier": "data:volume",
              "isDirectory": false,
              "isRegularFile": true,
              "isSymbolicLink": false,
              "isPackage": false,
              "isVolume": false,
              "fileSize": 32,
              "allocatedSize": 32,
              "modificationDate": 0
            }
            """.utf8
        )

        let identity = try JSONDecoder().decode(FilesystemIdentity.self, from: data)

        XCTAssertEqual(identity.fileResourceIdentifier, "data:file")
        XCTAssertNil(identity.hardLinkCount)
        XCTAssertNil(identity.fileIdentityKey)
        XCTAssertFalse(identity.digestComponent.contains("hard-link"))
    }

    func testLegacyNativeActionReceiptDecodingLeavesObservedFieldsNil() throws {
        let data = Data(
            """
            {
              "id": "legacy-receipt",
              "createdAt": 0,
              "kind": "homebrewCleanup",
              "mode": "dryRun",
              "commandDisplay": ["brew", "cleanup", "--dry-run"],
              "exitCode": 0,
              "stdoutPreview": ["Would remove one file"],
              "stderrPreview": [],
              "beforeDisk": null,
              "afterDisk": null,
              "skippedReason": null,
              "nonClaims": []
            }
            """.utf8
        )

        let receipt = try JSONDecoder().decode(NativeActionReceipt.self, from: data)

        XCTAssertEqual(receipt.id, "legacy-receipt")
        XCTAssertEqual(receipt.mode, .dryRun)
        XCTAssertNil(receipt.beforeObservedFreeBytes)
        XCTAssertNil(receipt.afterObservedFreeBytes)
        XCTAssertNil(receipt.observedReclaimBytes)
    }

    func testNativeActionReceiptDecodingRejectsDryRunAndNonPositiveObservedClaims() throws {
        let dryRunData = Data(
            """
            {
              "id": "dry-run-observed",
              "createdAt": 0,
              "kind": "homebrewCleanup",
              "mode": "dryRun",
              "commandDisplay": ["brew", "cleanup", "--dry-run"],
              "exitCode": 0,
              "stdoutPreview": [],
              "stderrPreview": [],
              "beforeDisk": null,
              "afterDisk": null,
              "skippedReason": null,
              "nonClaims": [],
              "beforeObservedFreeBytes": 100,
              "afterObservedFreeBytes": 300,
              "observedReclaimBytes": 200
            }
            """.utf8
        )
        let nonPositiveData = Data(
            """
            {
              "id": "negative-observed",
              "createdAt": 0,
              "kind": "homebrewCleanup",
              "mode": "perform",
              "commandDisplay": ["brew", "cleanup"],
              "exitCode": 0,
              "stdoutPreview": [],
              "stderrPreview": [],
              "beforeDisk": null,
              "afterDisk": null,
              "skippedReason": null,
              "nonClaims": [],
              "beforeObservedFreeBytes": 300,
              "afterObservedFreeBytes": 100,
              "observedReclaimBytes": -200
            }
            """.utf8
        )

        let dryRun = try JSONDecoder().decode(NativeActionReceipt.self, from: dryRunData)
        let nonPositive = try JSONDecoder().decode(NativeActionReceipt.self, from: nonPositiveData)

        XCTAssertNil(dryRun.observedReclaimBytes)
        XCTAssertNil(nonPositive.observedReclaimBytes)
    }

    func testNativeActionReceiptRecordsObservedDeltaOnlyForSuccessfulPerform() {
        let performed = NativeActionReceipt(
            kind: .homebrewCleanup,
            mode: .perform,
            commandDisplay: ["brew", "cleanup"],
            exitCode: 0,
            stdoutPreview: [],
            stderrPreview: [],
            beforeDisk: nil,
            afterDisk: nil,
            skippedReason: nil,
            nonClaims: [],
            beforeObservedFreeBytes: 1_000,
            afterObservedFreeBytes: 1_350
        )
        let dryRun = NativeActionReceipt(
            kind: .homebrewCleanup,
            mode: .dryRun,
            commandDisplay: ["brew", "cleanup", "--dry-run"],
            exitCode: 0,
            stdoutPreview: [],
            stderrPreview: [],
            beforeDisk: nil,
            afterDisk: nil,
            skippedReason: nil,
            nonClaims: [],
            beforeObservedFreeBytes: 1_000,
            afterObservedFreeBytes: 1_350
        )
        let negative = NativeActionReceipt(
            kind: .homebrewCleanup,
            mode: .perform,
            commandDisplay: ["brew", "cleanup"],
            exitCode: 0,
            stdoutPreview: [],
            stderrPreview: [],
            beforeDisk: nil,
            afterDisk: nil,
            skippedReason: nil,
            nonClaims: [],
            beforeObservedFreeBytes: 1_350,
            afterObservedFreeBytes: 1_000
        )

        XCTAssertEqual(performed.observedReclaimBytes, 350)
        XCTAssertNil(dryRun.observedReclaimBytes)
        XCTAssertNil(negative.observedReclaimBytes)
    }

    func testObservedReclaimCannotBeClaimedWithoutBothObservedSnapshots() {
        let receipt = NativeActionReceipt(
            kind: .homebrewCleanup,
            mode: .perform,
            commandDisplay: ["brew", "cleanup"],
            exitCode: 0,
            stdoutPreview: [],
            stderrPreview: [],
            beforeDisk: nil,
            afterDisk: nil,
            skippedReason: nil,
            nonClaims: [],
            beforeObservedFreeBytes: nil,
            afterObservedFreeBytes: 500
        )

        XCTAssertNil(receipt.observedReclaimBytes)
    }

    func testStorageAccountingUsesPlannedPhysicalReclaimStatusWireKey() throws {
        let accounting = StorageAccounting(
            logicalBytes: 100,
            allocatedBytes: 80,
            physicalReclaimStatus: .sharedCloneBacked
        )
        let data = try JSONEncoder().encode(accounting)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["physicalReclaimStatus"] as? String, "sharedCloneBacked")
        XCTAssertNil(object["status"])

        let legacy = try JSONSerialization.data(withJSONObject: [
            "logicalBytes": 100,
            "allocatedBytes": 80,
            "status": "estimated"
        ])
        XCTAssertEqual(try JSONDecoder().decode(StorageAccounting.self, from: legacy).physicalReclaimStatus, .estimated)
    }

    func testNativeReceiptBridgeCarriesObservedFreeSpaceEvidence() {
        let receipt = NativeActionReceipt(
            kind: .homebrewCleanup,
            mode: .perform,
            commandDisplay: ["brew", "cleanup"],
            exitCode: 0,
            stdoutPreview: [],
            stderrPreview: [],
            beforeDisk: nil,
            afterDisk: nil,
            skippedReason: nil,
            nonClaims: [],
            beforeObservedFreeBytes: 1_000,
            afterObservedFreeBytes: 1_350
        )

        let bridged = NativeActionReceiptBridge.nativeToolExecutionReceipt(
            from: receipt,
            ruleVersion: "test",
            findingPath: "/tmp/homebrew",
            userConfirmed: true
        )

        XCTAssertEqual(bridged.beforeFreeBytes, 1_000)
        XCTAssertEqual(bridged.afterFreeBytes, 1_350)
    }
}
