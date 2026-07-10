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

    func testReleaseCheckManifestAvoidsLocalAbsolutePaths() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(
            script.contains("assert_public_manifest_has_no_local_paths"),
            "release-check should fail if the public manifest leaks local build paths."
        )
        XCTAssertTrue(script.contains("Bundle: dist/Ryddi.app"))
        XCTAssertTrue(script.contains("Artifact: dist/$(basename \"$zip_path\")"))
        XCTAssertTrue(script.contains("Checksum: $artifact_sha  dist/$(basename \"$zip_path\")"))
        XCTAssertTrue(script.contains("- swift test --scratch-path .build"))
        XCTAssertFalse(script.contains("Bundle: $app"))
        XCTAssertFalse(script.contains("Artifact: $zip_path"))
        XCTAssertFalse(script.contains("$(cat \"$checksum_path\")"))
        XCTAssertFalse(script.contains("- swift test --scratch-path \"$root/.build\""))
    }

    func testReleaseCheckSmokesActualHomebrewReceiptGate() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("fake-brew-bin"))
        let fakeBrewSetup = try XCTUnwrap(script.range(of: "fake_brew_bin=\"$scratch/fake-brew-bin\""))
        let explicitPreview = try XCTUnwrap(script.range(of: "native run --dry-run --json"))
        XCTAssertLessThan(
            fakeBrewSetup.lowerBound,
            explicitPreview.lowerBound,
            "The explicit brew.preview smoke must install its disposable brew runner before invoking the now-real preview."
        )
        XCTAssertTrue(
            script.contains("grep -q \"Would remove Homebrew cache fixture\" \"$scratch/native-run-dry-run.json\"")
        )
        XCTAssertFalse(
            script.contains("grep -q \"Dry run only\" \"$scratch/native-run-dry-run.json\"")
        )
        XCTAssertTrue(script.contains("native homebrew cleanup --dry-run --save-audit"))
        XCTAssertTrue(script.contains("native receipts list --json"))
        XCTAssertTrue(script.contains("native receipts export"))
        XCTAssertTrue(script.contains("native homebrew cleanup --yes"))
        XCTAssertTrue(script.contains("requires a saved native dry-run receipt"))
        XCTAssertTrue(
            script.contains("bundled reclaimer native homebrew cleanup --dry-run/--yes receipt-gate smoke"),
            "The public manifest should record the stronger Homebrew preview/perform gate proof."
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
