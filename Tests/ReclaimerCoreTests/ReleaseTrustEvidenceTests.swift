import XCTest
@testable import ReclaimerCore

final class ReleaseTrustEvidenceTests: XCTestCase {
    func testNotNotarizedDoesNotBecomeReady() throws {
        let manifest = """
        version=0.2.0
        build=2
        codesign_verified=true
        hardened_runtime=true
        notarization_status=not notarized
        stapled=false
        gatekeeper=not assessed
        """

        let evidence = ReleaseTrustEvidenceParser.parseManifest(text: manifest, path: "/tmp/Ryddi-release-manifest.txt")

        XCTAssertEqual(evidence.state, .signedOnly)
        XCTAssertFalse(evidence.gatekeeperAccepted)
        XCTAssertEqual(evidence.notarizationStatus, "not notarized")
        XCTAssertTrue(evidence.warnings.contains { $0.contains("not accepted") })
    }

    func testAcceptedStapledGatekeeperManifestIsReleaseReady() throws {
        let manifest = """
        manifest_schema=ryddi.release-trust.v1
        version=0.3.0
        build=3
        artifact=Ryddi-v0.3.0.zip
        sha256=abc123
        source_commit=96c0d50
        codesign_verified=true
        hardened_runtime=true
        notarization_status=Accepted
        stapled=true
        gatekeeper=accepted
        """

        let evidence = ReleaseTrustEvidenceParser.parseManifest(text: manifest, path: "/tmp/Ryddi-release-manifest.txt")

        XCTAssertEqual(evidence.state, .stapledAndAccepted)
        XCTAssertEqual(evidence.version, "0.3.0")
        XCTAssertEqual(evidence.buildNumber, "3")
        XCTAssertEqual(evidence.artifactName, "Ryddi-v0.3.0.zip")
        XCTAssertEqual(evidence.artifactSHA256, "abc123")
        XCTAssertEqual(evidence.sourceCommit, "96c0d50")
        XCTAssertTrue(evidence.codesignVerified)
        XCTAssertTrue(evidence.hardenedRuntime)
        XCTAssertTrue(evidence.stapleValidated)
        XCTAssertTrue(evidence.gatekeeperAccepted)
        XCTAssertTrue(evidence.warnings.isEmpty)
    }

    func testAcceptedButNotStapledIsNotReleaseReady() throws {
        let manifest = """
        codesign_verified=true
        hardened_runtime=true
        notarization_status=Accepted
        stapled=false
        gatekeeper=accepted
        """

        let evidence = ReleaseTrustEvidenceParser.parseManifest(text: manifest, path: nil)

        XCTAssertEqual(evidence.state, .notarizationAccepted)
        XCTAssertFalse(evidence.stapleValidated)
        XCTAssertTrue(evidence.warnings.contains { $0.contains("Stapling") })
    }

    func testMissingManifestIsExplicitState() throws {
        let evidence = ReleaseTrustEvidenceLoader.load(path: "/tmp/ryddi-definitely-missing-\(UUID().uuidString).txt")

        XCTAssertEqual(evidence.state, .missingManifest)
        XCTAssertFalse(evidence.codesignVerified)
        XCTAssertFalse(evidence.gatekeeperAccepted)
        XCTAssertTrue(evidence.warnings.contains { $0.contains("No release manifest") })
    }

    func testTrustReadinessUsesTypedReleaseEvidenceNotSubstring() throws {
        let permissionReport = PermissionAdvisor.report(
            scopeSummaries: [
                ScopeAccessSummary(name: "Caches", path: "/fixture/Library/Caches", permissionState: .readable, message: "Directory is readable.")
            ],
            now: Date(timeIntervalSince1970: 0)
        )
        let falsePositive = ReleaseTrustEvidenceParser.parseManifest(
            text: """
            codesign_verified=true
            hardened_runtime=true
            notarization_status=not notarized
            stapled=false
            gatekeeper=not assessed
            """,
            path: "/tmp/Ryddi-release-manifest.txt"
        )

        let report = TrustReadinessBuilder.build(
            diskStatus: DiskStatusSnapshot(
                createdAt: Date(timeIntervalSince1970: 0),
                path: "/fixture",
                totalBytes: 1_000,
                freeBytes: 900,
                importantFreeBytes: nil,
                availableBytes: nil,
                pressure: .healthy,
                notes: []
            ),
            permissionSummary: permissionReport,
            latestReceipt: nil,
            automationInstalled: true,
            signingState: "signed and notarized string should not decide readiness",
            releaseTrustEvidence: falsePositive
        )

        let releaseAction = try XCTUnwrap(report.recommendedActions.first { $0.id == "release.trust" })
        XCTAssertEqual(releaseAction.severity, .warning)
        XCTAssertEqual(report.releaseTrustEvidence.state, .signedOnly)
    }

    func testReleaseCheckWritesParseableManifestKeys() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("manifest_schema=ryddi.release-trust.v1"))
        XCTAssertTrue(script.contains("codesign_verified=$codesign_verified"))
        XCTAssertTrue(script.contains("hardened_runtime=$hardened_runtime"))
        XCTAssertTrue(script.contains("notarization_status=$notarization_status"))
        XCTAssertTrue(script.contains("stapled=$stapled"))
        XCTAssertTrue(script.contains("gatekeeper=$gatekeeper_status"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
