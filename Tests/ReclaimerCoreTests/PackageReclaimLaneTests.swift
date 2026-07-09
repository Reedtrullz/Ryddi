import XCTest
@testable import ReclaimerCore

final class PackageReclaimLaneTests: XCTestCase {
    func testNpmCacheProducesPreviewOnlyNativeLane() throws {
        let report = PackageCacheFixtures.report(manager: "npm", bytes: 2_000_000_000)

        let lane = PackageReclaimLaneBuilder.build(from: report, generatedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(lane.totalPreviewBytes, 2_000_000_000)
        XCTAssertEqual(lane.managerReports.first?.managerName, "npm")
        XCTAssertEqual(lane.managerReports.first?.previewCommand, ["npm", "cache", "verify"])
        XCTAssertEqual(lane.managerReports.first?.cleanupCommand, ["npm", "cache", "clean", "--force"])
        XCTAssertEqual(lane.managerReports.first?.previewOnly, true)
        XCTAssertTrue(lane.nonClaims.contains("No package cache cleanup was executed."))
    }

    func testHomebrewCacheProducesDryRunCleanupPreview() throws {
        let report = PackageCacheFixtures.report(manager: "Homebrew", bytes: 1_500_000_000)

        let lane = PackageReclaimLaneBuilder.build(from: report)

        XCTAssertEqual(lane.managerReports.first?.id, "homebrew")
        XCTAssertEqual(lane.managerReports.first?.previewCommand, ["brew", "cleanup", "--dry-run"])
        XCTAssertEqual(lane.managerReports.first?.cleanupCommand, ["brew", "cleanup"])
    }

    func testUnsupportedManagerStaysManualGuidance() throws {
        let report = PackageCacheFixtures.report(manager: "unknownpkg", bytes: 500_000_000)

        let lane = PackageReclaimLaneBuilder.build(from: report)

        XCTAssertEqual(lane.totalPreviewBytes, 0)
        XCTAssertTrue(lane.managerReports.allSatisfy(\.previewOnly))
        XCTAssertTrue(lane.managerReports.first?.previewCommand.isEmpty == true)
        XCTAssertTrue(lane.managerReports.first?.cleanupCommand.isEmpty == true)
        XCTAssertTrue(lane.managerReports.first?.explanation.localizedCaseInsensitiveContains("manual") == true)
    }

    func testMultipleManagersSortByLargestPreviewBytes() throws {
        let report = PackageCacheFixtures.report(
            summaries: [
                PackageCacheSummary(name: "npm", itemCount: 1, allocatedSize: 1_000),
                PackageCacheSummary(name: "Homebrew", itemCount: 1, allocatedSize: 5_000),
                PackageCacheSummary(name: "unknownpkg", itemCount: 1, allocatedSize: 10_000)
            ]
        )

        let lane = PackageReclaimLaneBuilder.build(from: report)

        XCTAssertEqual(lane.managerReports.map(\.managerName), ["unknownpkg", "Homebrew", "npm"])
        XCTAssertEqual(lane.totalPreviewBytes, 6_000)
    }

    func testPackageManagerCommandCardsStayGuidanceFirst() throws {
        let report = PackageCacheFixtures.report(
            summaries: [
                PackageCacheSummary(name: "npm", itemCount: 1, allocatedSize: 1_000),
                PackageCacheSummary(name: "pnpm", itemCount: 1, allocatedSize: 2_000),
                PackageCacheSummary(name: "yarn", itemCount: 1, allocatedSize: 3_000)
            ]
        )

        let lane = PackageReclaimLaneBuilder.build(from: report)
        let npm = try XCTUnwrap(lane.managerReports.first { $0.id == "npm" })
        let pnpm = try XCTUnwrap(lane.managerReports.first { $0.id == "pnpm" })
        let yarn = try XCTUnwrap(lane.managerReports.first { $0.id == "yarn" })

        XCTAssertEqual(npm.commandCards.first { $0.id == "npm.verify" }?.argv, ["npm", "cache", "verify"])
        XCTAssertEqual(npm.commandCards.first { $0.id == "npm.clean" }?.review, .manualReview)
        XCTAssertEqual(pnpm.commandCards.first { $0.id == "pnpm.status" }?.argv, ["pnpm", "store", "status"])
        XCTAssertEqual(pnpm.commandCards.first { $0.id == "pnpm.prune" }?.review, .manualReview)
        XCTAssertEqual(yarn.commandCards.first { $0.id == "yarn.clean-dry-run" }?.argv, ["yarn", "cache", "clean", "--dry-run"])
        XCTAssertEqual(yarn.commandCards.first { $0.id == "yarn.clean-dry-run" }?.dryRunSupport, .versionDependent)
        XCTAssertTrue(lane.managerReports.allSatisfy(\.previewOnly))
    }
}

private enum PackageCacheFixtures {
    static func report(manager: String, bytes: Int64) -> PackageCacheReviewReport {
        report(summaries: [PackageCacheSummary(name: manager, itemCount: 1, allocatedSize: bytes)])
    }

    static func report(summaries: [PackageCacheSummary]) -> PackageCacheReviewReport {
        let bytes = summaries.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let itemCount = summaries.reduce(0) { $0 + $1.itemCount }
        return PackageCacheReviewReport(
            totalLogicalSize: bytes,
            totalAllocatedSize: bytes,
            itemCount: itemCount,
            displayedItemCount: itemCount,
            candidateBytes: bytes,
            rootSummaries: [],
            managerSummaries: summaries,
            kindSummaries: [],
            largestItems: [],
            protectedConfigRoots: [],
            guidance: ["Fixture guidance"],
            nonClaims: ["Fixture report did not clean anything."]
        )
    }
}
