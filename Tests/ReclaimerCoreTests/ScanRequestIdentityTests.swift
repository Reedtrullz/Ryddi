import XCTest
@testable import ReclaimerCore

final class ScanRequestIdentityTests: XCTestCase {
    func testOnlyLatestRequestMayFinish() {
        var coordinator = ScanRequestCoordinator()
        let first = makeRequest(scope: "first")
        let second = makeRequest(scope: "second")

        coordinator.begin(first)
        coordinator.begin(second)

        XCTAssertFalse(coordinator.finish(first))
        XCTAssertTrue(coordinator.accepts(second))
        XCTAssertTrue(coordinator.finish(second))
        XCTAssertNil(coordinator.activeRequest)
    }

    func testInvalidationRejectsLateResult() {
        var coordinator = ScanRequestCoordinator()
        let request = makeRequest(scope: "scope")

        coordinator.begin(request)
        coordinator.invalidate()

        XCTAssertFalse(coordinator.accepts(request))
        XCTAssertFalse(coordinator.finish(request))
    }

    func testRequestIdentityIncludesEveryScanConfigurationDigest() {
        let baseline = makeRequest(scope: "scope")

        XCTAssertNotEqual(baseline, makeRequest(scope: "other"))
        XCTAssertNotEqual(baseline, makeRequest(scope: "scope", ruleVersion: "other"))
        XCTAssertNotEqual(baseline, makeRequest(scope: "scope", policyDigest: "other"))
        XCTAssertNotEqual(baseline, makeRequest(scope: "scope", preset: .general))
    }

    private func makeRequest(
        scope: String,
        ruleVersion: String = "rules",
        policyDigest: String = "policy",
        preset: ScanScopePreset = .developer
    ) -> ScanRequestIdentity {
        ScanRequestIdentity(
            id: UUID(),
            preset: preset,
            scopeDigest: scope,
            ruleVersion: ruleVersion,
            policyDigest: policyDigest
        )
    }
}
