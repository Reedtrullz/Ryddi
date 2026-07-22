import XCTest
@testable import ReclaimerCore

final class SafetyCheckerTests: XCTestCase {
    let checker = SafetyChecker()

    func testDowngradesPathOutsideRoot() {
        let rec = ReclaimRecommendation(
            path: "/outside/file", category: .oldLog,
            reclaimableBytes: 100, safetyScore: 0.9, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let result = checker.check([rec], scanRoot: "/tmp/scan")
        XCTAssertEqual(result.first?.safetyScore, 0.1)
        XCTAssertEqual(result.first?.action, .reviewRequired)
    }

    func testGitPathGetsReviewRequired() {
        let rec = ReclaimRecommendation(
            path: "/tmp/scan/.git/objects/pack", category: .gitBloat,
            reclaimableBytes: 100, safetyScore: 0.9, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let result = checker.check([rec], scanRoot: "/tmp/scan")
        XCTAssertEqual(result.first?.action, .reviewRequired)
        XCTAssertTrue(result.first?.description.contains("git gc") == true)
    }

    func testDefaultSafetyBuildArtifact() {
        let rec = ReclaimRecommendation(
            path: "/tmp/scan/build", category: .buildArtifact,
            reclaimableBytes: 100, safetyScore: 0.5, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let result = checker.check([rec], scanRoot: "/tmp/scan")
        XCTAssertEqual(result.first?.safetyScore, 0.9)
    }

    func testDefaultSafetyDuplicateFile() {
        let rec = ReclaimRecommendation(
            path: "/tmp/scan/dup", category: .duplicateFile,
            reclaimableBytes: 100, safetyScore: 0.5, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let result = checker.check([rec], scanRoot: "/tmp/scan")
        XCTAssertEqual(result.first?.safetyScore, 0.8)
        XCTAssertEqual(result.first?.effortScore, 0.6)
    }

    func testDefaultSafetyGitBloat() {
        let rec = ReclaimRecommendation(
            path: "/tmp/scan/git", category: .gitBloat,
            reclaimableBytes: 100, safetyScore: 0.5, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let result = checker.check([rec], scanRoot: "/tmp/scan")
        XCTAssertEqual(result.first?.safetyScore, 0.2)
        XCTAssertEqual(result.first?.effortScore, 0.2)
    }

    func testPreservesExplicitSafetyScore() {
        let rec = ReclaimRecommendation(
            path: "/tmp/scan/explicit", category: .oldLog,
            reclaimableBytes: 100, safetyScore: 0.95, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let result = checker.check([rec], scanRoot: "/tmp/scan")
        XCTAssertEqual(result.first?.safetyScore, 0.95)
    }
}
