import Darwin
import Foundation
import XCTest
@testable import ReclaimerCore
@testable import reclaimer

final class RemoteCLIPolishTests: XCTestCase {
    func testRemoteScanTextShowsGroupedCommandCardsAndBucketChanges() throws {
        let report = RemoteScanReport(
            preset: .vpsGeneral,
            target: RemoteTargetReference(input: "prod-vps", alias: "prod-vps"),
            diskFilesystems: [],
            inodeFilesystems: [],
            findings: [
                RemoteStorageFinding(
                    remotePath: "docker://images",
                    displayPath: "docker://images",
                    bucket: "Docker images",
                    allocatedBytes: 2_048,
                    safetyClass: .safeAfterCondition,
                    actionKind: .nativeToolCommand,
                    evidence: [Evidence(kind: "remote.docker", message: "Fixture.")],
                    recommendedNextAction: .useNativeTool
                )
            ],
            nativeGuidance: [],
            commands: [],
            nonClaims: RemoteScanReport.defaultNonClaims
        )
        let growth = RemoteGrowthSummary(
            targetID: "prod-vps",
            previousScanID: "previous",
            currentScanID: report.id,
            changedBuckets: [
                RemoteBucketGrowth(bucket: "Docker images", previousBytes: 1_024, currentBytes: 2_048, deltaBytes: 1_024)
            ],
            unavailableReason: nil
        )

        let output = try captureStandardOutput {
            printRemoteScanReport(report, title: "Remote Scan Report", growthSummary: growth)
        }

        XCTAssertTrue(output.contains("Manual command cards"))
        XCTAssertTrue(output.contains("docker"))
        XCTAssertTrue(output.contains("docker system prune"))
        XCTAssertTrue(output.contains("Saved bucket changes"))
        XCTAssertTrue(output.contains("Docker images"))
    }

    private func captureStandardOutput(_ body: () throws -> Void) throws -> String {
        let original = dup(STDOUT_FILENO)
        XCTAssertGreaterThanOrEqual(original, 0)
        var fds = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(pipe(&fds), 0)

        fflush(stdout)
        dup2(fds[1], STDOUT_FILENO)
        close(fds[1])

        do {
            try body()
            fflush(stdout)
            dup2(original, STDOUT_FILENO)
            close(original)
        } catch {
            fflush(stdout)
            dup2(original, STDOUT_FILENO)
            close(original)
            close(fds[0])
            throw error
        }

        let data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
