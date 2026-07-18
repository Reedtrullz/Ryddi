import Foundation
import XCTest
@testable import RyddiProtectCore

final class CloudOrganizationTests: XCTestCase {
    func testBuildsLargeStaleAndHashProvenDuplicateReviewQueues() throws {
        let old = Date(timeIntervalSince1970: 1_000)
        let objects = try [
            object("a", name: "Archive A.zip", bytes: 2_000, date: old, hash: "same"),
            object("b", name: "Archive B.zip", bytes: 2_000, date: old, hash: "same"),
            object("c", name: "Large.mov", bytes: 3_000, date: nil, hash: nil)
        ]
        let report = CloudOrganizationBuilder.build(
            inventory: inventory(objects),
            policy: CloudOrganizationPolicy(largeFileBytes: 1_500, staleAge: 100),
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(report.duplicateGroups.count, 1)
        XCTAssertEqual(report.duplicateGroups.first?.potentialDuplicateBytes, 2_000)
        XCTAssertEqual(report.largeObjects.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(Set(report.staleObjects.map(\.id)), ["a", "b"])
        XCTAssertEqual(report.unknownDateCount, 1)
    }

    func testNamesAndSizesAloneNeverCreateDuplicateProof() throws {
        let objects = try [
            object("a", name: "same.txt", bytes: 100, date: nil, hash: nil),
            object("b", name: "same.txt", bytes: 100, date: nil, hash: nil)
        ]
        let report = CloudOrganizationBuilder.build(inventory: inventory(objects))
        XCTAssertTrue(report.duplicateGroups.isEmpty)
        XCTAssertTrue(report.nonClaims.contains { $0.contains("names or sizes alone") })
    }

    func testMegaFingerprintDoesNotCreateCryptographicDuplicateProof() throws {
        let objects = try [
            object("a", name: "one.bin", bytes: 100, date: nil, hash: "fingerprint", hashKind: .megaFingerprint),
            object("b", name: "two.bin", bytes: 100, date: nil, hash: "fingerprint", hashKind: .megaFingerprint)
        ]
        XCTAssertTrue(CloudOrganizationBuilder.build(inventory: inventory(objects)).duplicateGroups.isEmpty)
    }

    func testDifferentHashAlgorithmsNeverShareDuplicateBucket() throws {
        let objects = try [
            object("a", name: "one.bin", bytes: 100, date: nil, hash: "same-text", hashKind: .md5),
            object("b", name: "two.bin", bytes: 100, date: nil, hash: "same-text", hashKind: .sha256)
        ]
        XCTAssertTrue(CloudOrganizationBuilder.build(inventory: inventory(objects)).duplicateGroups.isEmpty)
    }

    private func object(
        _ id: String,
        name: String,
        bytes: Int64,
        date: Date?,
        hash: String?,
        hashKind: CloudObjectHashKind? = .dropboxContentHash
    ) throws -> CloudObjectReference {
        try CloudObjectReference(
            id: id,
            provider: .dropbox,
            displayName: name,
            objectKind: .file,
            logicalBytes: bytes,
            modifiedAt: date,
            providerHash: hash,
            providerHashKind: hash == nil ? nil : hashKind
        )
    }

    private func inventory(_ objects: [CloudObjectReference]) -> CloudInventoryReport {
        CloudInventoryReport(
            provider: .dropbox,
            connection: nil,
            objects: objects,
            logicalBytes: objects.compactMap(\.logicalBytes).reduce(0, +),
            pageCount: 1,
            responseByteCount: 100,
            retryCount: 0,
            completion: .complete,
            issue: nil,
            nonClaims: []
        )
    }
}
