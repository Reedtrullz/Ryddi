import Foundation
import XCTest
@testable import ReclaimerCore

final class RuntimeTrustDashboardContractTests: XCTestCase {
    func testRuntimeTrustSummariesKeepSignatureGatekeeperAndManifestDistinct() {
        let report = runtimeReport(
            signature: .developerIDSigned,
            gatekeeper: .gatekeeperAccepted,
            externalManifest: ReleaseTrustEvidence(state: .stapledAndAccepted)
        )

        XCTAssertEqual(report.signatureSummary, "Developer ID signed")
        XCTAssertEqual(report.gatekeeperSummary, "Gatekeeper accepted")
        XCTAssertEqual(report.externalManifestSummary, "Release ready")
        XCTAssertFalse(report.gatekeeperSummary.localizedCaseInsensitiveContains("notarized"))
        XCTAssertFalse(report.gatekeeperSummary.localizedCaseInsensitiveContains("stapled"))
    }

    func testRuntimeTrustSummariesExposeUnsignedRejectedAndUnavailableStates() {
        let unsigned = runtimeReport(signature: .unsigned, gatekeeper: .gatekeeperRejectedUnnotarized)
        let unavailable = runtimeReport(signature: .unavailable, gatekeeper: .unavailable)

        XCTAssertEqual(unsigned.signatureSummary, "Unsigned")
        XCTAssertEqual(unsigned.gatekeeperSummary, "Gatekeeper rejected: unnotarized")
        XCTAssertEqual(unsigned.externalManifestSummary, "Not provided")
        XCTAssertEqual(unavailable.signatureSummary, "Unable to verify")
        XCTAssertEqual(unavailable.gatekeeperSummary, "Unable to verify")
    }

    func testTrustReadinessCarriesRuntimeReportWithoutPromotingExternalManifest() throws {
        let runtime = runtimeReport(signature: .developerIDSigned, gatekeeper: .gatekeeperAccepted)
        let report = TrustReadinessBuilder.build(
            diskStatus: diskStatus,
            permissionSummary: permissionReport,
            runtimeReleaseTrustReport: runtime
        )

        XCTAssertEqual(report.runtimeReleaseTrustReport, runtime)
        XCTAssertEqual(report.releaseTrustEvidence.state, .missingManifest)
        XCTAssertEqual(report.recommendedActions.first { $0.id == "release.runtime-signature" }?.detail, "Developer ID signed")
        XCTAssertEqual(report.recommendedActions.first { $0.id == "release.runtime-gatekeeper" }?.detail, "Gatekeeper accepted")
        XCTAssertEqual(report.recommendedActions.first { $0.id == "release.external-manifest" }?.detail, "Not provided")
        XCTAssertTrue(report.nonClaims.contains { $0.contains("Gatekeeper acceptance") && $0.contains("stapling") })
    }

    func testDashboardModelRunsOneRuntimeProbeOffMainAndStoresTypedReport() throws {
        let source = try appSource("DashboardModel.swift")

        XCTAssertTrue(source.contains("var runtimeReleaseTrustReport: RuntimeReleaseTrustReport?"))
        XCTAssertEqual(source.components(separatedBy: "RuntimeReleaseTrustProbe().inspect()").count - 1, 1)
        XCTAssertTrue(source.contains("Task.detached"))
        XCTAssertTrue(source.contains("runtimeReleaseTrustReport = report"))
        XCTAssertTrue(source.contains("runtimeReleaseTrustReport: runtimeReleaseTrustReport"))
        XCTAssertFalse(source.contains("ReleaseTrustEvidenceLoader.load()"))
    }

    func testTrustReadinessViewRendersLoadingRuntimeAndExternalStatesWithoutRunningTools() throws {
        let source = try appSource("DashboardContentViews.swift")
        let view = try sourceSlice(
            source,
            from: "struct TrustReadinessCardsView",
            through: "struct TrustReadinessActionRow"
        )

        XCTAssertTrue(view.contains("title: \"Signature\""))
        XCTAssertTrue(view.contains("title: \"Gatekeeper\""))
        XCTAssertTrue(view.contains("title: \"External Manifest\""))
        XCTAssertTrue(view.contains("?? \"Loading...\""))
        XCTAssertFalse(view.contains("codesign"))
        XCTAssertFalse(view.contains("spctl"))
        XCTAssertFalse(view.contains("RuntimeReleaseTrustProbe"))
    }

    private var diskStatus: DiskStatusSnapshot {
        DiskStatusSnapshot(
            createdAt: Date(timeIntervalSince1970: 0),
            path: "/fixture",
            totalBytes: 1_000,
            freeBytes: 900,
            importantFreeBytes: nil,
            availableBytes: nil,
            pressure: .healthy,
            notes: []
        )
    }

    private var permissionReport: PermissionAdvisorReport {
        PermissionAdvisor.report(
            scopeSummaries: [
                ScopeAccessSummary(
                    name: "Caches",
                    path: "/fixture/Library/Caches",
                    permissionState: .readable,
                    message: "Directory is readable."
                )
            ],
            now: Date(timeIntervalSince1970: 0)
        )
    }

    private func runtimeReport(
        signature: RuntimeTrustState,
        gatekeeper: RuntimeTrustState,
        externalManifest: ReleaseTrustEvidence? = nil
    ) -> RuntimeReleaseTrustReport {
        RuntimeReleaseTrustReport(
            build: nil,
            signature: RuntimeTrustCheck(state: signature, detail: "signature detail"),
            gatekeeper: RuntimeTrustCheck(state: gatekeeper, detail: "gatekeeper detail"),
            externalManifest: externalManifest,
            claims: [],
            nonClaims: []
        )
    }

    private func appSource(_ filename: String) throws -> String {
        try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/MacDiskReclaimerApp/\(filename)"),
            encoding: .utf8
        )
    }

    private func sourceSlice(_ source: String, from start: String, through end: String) throws -> String {
        let startIndex = try XCTUnwrap(source.range(of: start)?.lowerBound)
        let endIndex = try XCTUnwrap(source.range(of: end, range: startIndex..<source.endIndex)?.lowerBound)
        return String(source[startIndex..<endIndex])
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
