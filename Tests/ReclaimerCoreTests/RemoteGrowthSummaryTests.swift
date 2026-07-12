import XCTest
@testable import ReclaimerCore

final class RemoteGrowthSummaryTests: XCTestCase {
    func testComparesSavedScansForSameTargetAcrossRemoteBuckets() throws {
        let target = concreteTarget(host: "203.0.113.10")
        let previous = scan(
            id: "previous",
            target: target,
            diskBytes: 1_000,
            inodeBytes: 100,
            findings: [
                finding(bucket: "Journald logs", bytes: 20),
                finding(bucket: "APT cache", bytes: 30),
                finding(bucket: "Docker images", bytes: 40),
                finding(bucket: "Docker build cache", bytes: 50),
                finding(bucket: "Docker volumes", bytes: 60),
                finding(bucket: "Large remote files", bytes: 70),
                finding(bucket: "Old deploy releases", bytes: 80)
            ]
        )
        let current = scan(
            id: "current",
            target: target,
            diskBytes: 1_500,
            inodeBytes: 90,
            findings: [
                finding(bucket: "Journald logs", bytes: 25),
                finding(bucket: "APT cache", bytes: 10),
                finding(bucket: "Docker images", bytes: 100),
                finding(bucket: "Docker build cache", bytes: 55),
                finding(bucket: "Docker volumes", bytes: 90),
                finding(bucket: "Large remote files", bytes: 170),
                finding(bucket: "Old deploy releases", bytes: 100)
            ]
        )

        let summary = RemoteGrowthSummaryBuilder.build(previous: previous, current: current)
        let buckets = Dictionary(uniqueKeysWithValues: summary.changedBuckets.map { ($0.bucket, $0) })

        XCTAssertNil(summary.unavailableReason)
        XCTAssertEqual(summary.previousScanID, "previous")
        XCTAssertEqual(summary.currentScanID, "current")
        XCTAssertEqual(summary.targetID, target.id)
        XCTAssertEqual(buckets["Disk filesystems"]?.deltaBytes, 500)
        XCTAssertEqual(buckets["Inode filesystems"]?.deltaBytes, -10)
        XCTAssertEqual(buckets["Journald logs"]?.deltaBytes, 5)
        XCTAssertEqual(buckets["APT cache"]?.deltaBytes, -20)
        XCTAssertEqual(buckets["Docker images"]?.deltaBytes, 60)
        XCTAssertEqual(buckets["Docker build cache"]?.deltaBytes, 5)
        XCTAssertEqual(buckets["Docker volumes"]?.deltaBytes, 30)
        XCTAssertEqual(buckets["Large remote files"]?.deltaBytes, 100)
        XCTAssertEqual(buckets["Old deploy releases"]?.deltaBytes, 20)
    }

    func testNoPreviousScanReturnsUnavailableReason() throws {
        let current = scan(id: "current", target: concreteTarget(), diskBytes: 1_000, inodeBytes: 100, findings: [])

        let summary = RemoteGrowthSummaryBuilder.build(previous: nil, current: current)

        XCTAssertEqual(summary.previousScanID, nil)
        XCTAssertTrue(summary.changedBuckets.isEmpty)
        XCTAssertTrue(summary.unavailableReason?.contains("No previous remote scan") == true)
    }

    func testChangedTargetIdentityReturnsUnavailableReason() throws {
        let previous = scan(id: "previous", target: concreteTarget(host: "203.0.113.10"), diskBytes: 1_000, inodeBytes: 100, findings: [
            finding(bucket: "Docker images", bytes: 40)
        ])
        let current = scan(id: "current", target: concreteTarget(host: "203.0.113.11"), diskBytes: 2_000, inodeBytes: 200, findings: [
            finding(bucket: "Docker images", bytes: 400)
        ])

        let summary = RemoteGrowthSummaryBuilder.build(previous: previous, current: current)

        XCTAssertTrue(summary.changedBuckets.isEmpty)
        XCTAssertTrue(summary.unavailableReason?.contains("host") == true)
    }

    func testUnresolvedDifferentAliasesAreNotCompared() throws {
        let previous = scan(id: "previous", target: RemoteTargetReference(input: "prod-vps"), diskBytes: 1_000, inodeBytes: 100, findings: [])
        let current = scan(id: "current", target: RemoteTargetReference(input: "stage-vps"), diskBytes: 2_000, inodeBytes: 200, findings: [])

        let summary = RemoteGrowthSummaryBuilder.build(previous: previous, current: current)

        XCTAssertTrue(summary.changedBuckets.isEmpty)
        XCTAssertTrue(summary.unavailableReason?.contains("unresolved") == true)
    }

    func testUserAndPortAloneAreNotConcreteTargetIdentity() throws {
        let previous = scan(
            id: "previous",
            target: RemoteTargetReference(input: "prod-vps", resolvedUser: "deploy", resolvedPort: 22),
            diskBytes: 1_000,
            inodeBytes: 100,
            findings: []
        )
        let current = scan(
            id: "current",
            target: RemoteTargetReference(input: "stage-vps", resolvedUser: "deploy", resolvedPort: 22),
            diskBytes: 2_000,
            inodeBytes: 200,
            findings: []
        )

        let summary = RemoteGrowthSummaryBuilder.build(previous: previous, current: current)

        XCTAssertTrue(summary.changedBuckets.isEmpty)
        XCTAssertTrue(summary.unavailableReason?.contains("unresolved") == true)
    }

    func testDifferentAliasesWithSameConcreteIdentityCanCompare() throws {
        let previous = scan(id: "previous", target: concreteTarget(input: "prod-a", alias: "prod-a"), diskBytes: 1_000, inodeBytes: 100, findings: [])
        let current = scan(id: "current", target: concreteTarget(input: "prod-b", alias: "prod-b"), diskBytes: 1_500, inodeBytes: 100, findings: [])

        let summary = RemoteGrowthSummaryBuilder.build(previous: previous, current: current)

        XCTAssertNil(summary.unavailableReason)
        XCTAssertEqual(summary.changedBuckets.first { $0.bucket == "Disk filesystems" }?.deltaBytes, 500)
    }

    private func concreteTarget(input: String = "prod-vps", alias: String? = "prod-vps", host: String = "203.0.113.10") -> RemoteTargetReference {
        RemoteTargetReference(
            input: input,
            alias: alias,
            resolvedUser: "deploy",
            resolvedHost: host,
            resolvedPort: 22,
            knownHostsState: "known",
            fingerprint: "ssh-ed25519:fixture"
        )
    }

    private func scan(
        id: String,
        target: RemoteTargetReference,
        diskBytes: Int64,
        inodeBytes: Int64,
        findings: [RemoteStorageFinding]
    ) -> RemoteScanReport {
        RemoteScanReport(
            id: id,
            preset: .vpsGeneral,
            target: target,
            diskFilesystems: [
                RemoteFilesystemSummary(mount: "/", filesystem: "/dev/vda1", usedBytes: diskBytes, availableBytes: nil, capacityPercent: nil)
            ],
            inodeFilesystems: [
                RemoteFilesystemSummary(mount: "/", filesystem: "/dev/vda1", usedBytes: inodeBytes, availableBytes: nil, capacityPercent: nil)
            ],
            findings: findings,
            nativeGuidance: [],
            commands: [],
            nonClaims: RemoteScanReport.defaultNonClaims
        )
    }

    private func finding(bucket: String, bytes: Int64) -> RemoteStorageFinding {
        RemoteStorageFinding(
            remotePath: "remote://\(bucket.lowercased().replacingOccurrences(of: " ", with: "-"))",
            displayPath: bucket,
            bucket: bucket,
            allocatedBytes: bytes,
            safetyClass: .reviewRequired,
            actionKind: .openGuidance,
            evidence: [Evidence(kind: "remote.fixture", message: "Fixture evidence.")],
            recommendedNextAction: .reviewInFinder
        )
    }
}
