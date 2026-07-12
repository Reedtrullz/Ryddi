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

        let releaseAction = try XCTUnwrap(report.recommendedActions.first { $0.id == "release.external-manifest" })
        XCTAssertEqual(releaseAction.severity, .warning)
        XCTAssertEqual(report.releaseTrustEvidence.state, .signedOnly)
    }

    func testReleaseCheckWritesParseableManifestKeys() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("manifest_schema=ryddi.release-trust.v1"))
        XCTAssertTrue(script.contains("codesign_verified=$codesign_verified"))
        XCTAssertTrue(script.contains("hardened_runtime=$hardened_runtime"))
        XCTAssertTrue(script.contains("notarization_status=$notarization_status"))
        XCTAssertTrue(script.contains("stapler_validated=$stapler_validated"))
        XCTAssertTrue(script.contains("stapled=$stapler_validated"))
        XCTAssertTrue(script.contains("gatekeeper=$gatekeeper_status"))
    }

    func testReleaseCheckManifestAvoidsLocalAbsolutePaths() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(
            script.contains("assert_public_manifest_has_no_local_paths"),
            "release-check should fail if the public manifest leaks local build paths."
        )
        XCTAssertTrue(script.contains("Artifact directory: $artifact_basename"))
        XCTAssertTrue(script.contains("App payload SHA-256: $app_payload_sha"))
        XCTAssertTrue(script.contains("printf '%s  %s\\n' \"$app_payload_sha\" \"Ryddi.app\""))
        XCTAssertTrue(script.contains("/usr/bin/ditto -c -k --keepParent \"$stage_dir\" \"$zip_path\""))
        XCTAssertFalse(script.contains("Bundle: $app"))
        XCTAssertFalse(script.contains("Artifact: $zip_path"))
        XCTAssertFalse(script.contains("$(cat \"$checksum_path\")"))
        XCTAssertFalse(script.contains("- swift test --scratch-path \"$root/.build\""))
    }

    func testReleaseCheckSmokesFreshSameProcessHomebrewPreview() throws {
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
        XCTAssertTrue(script.contains("native-homebrew-fresh-perform.json"))
        XCTAssertTrue(script.contains("native-homebrew-fresh-receipts.json"))
        XCTAssertTrue(script.contains("grep -q '\"id\" : \"brew.preview\"' \"$scratch/native-homebrew-fresh-receipts.json\""))
        XCTAssertTrue(script.contains("grep -q '\"id\" : \"brew.cleanup\"' \"$scratch/native-homebrew-fresh-receipts.json\""))
        XCTAssertTrue(script.contains("grep -q '\"status\" : \"dry-run\"' \"$scratch/native-homebrew-fresh-receipts.json\""))
        XCTAssertTrue(script.contains("grep -q '\"status\" : \"done\"' \"$scratch/native-homebrew-fresh-receipts.json\""))
        XCTAssertTrue(script.contains("audit-homebrew-fresh\" -name 'native-tool-execution-*.json' -type f | wc -l"))
        XCTAssertTrue(script.contains("Removed Homebrew cache fixture"))
        XCTAssertTrue(script.contains("recovery restore \"2026-01-01T00-00-00Z/cache.bin\""))
        XCTAssertTrue(script.contains("unexpectedly succeeded"))
        XCTAssertFalse(script.contains("requires a saved native dry-run receipt"))
        XCTAssertFalse(script.contains("requires a saved Homebrew dry-run receipt"))
        XCTAssertTrue(
            script.contains("native homebrew cleanup --yes --save-audit"),
            "The release gate should still run the same-process Homebrew preview/perform proof."
        )
    }

    func testReleaseCheckRefusesToReplaceExistingCLIOutput() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("permissions-guide-existing.md"))
        XCTAssertTrue(script.contains("existing permission guide output"))
        XCTAssertTrue(script.contains("keep existing output"))
    }

    func testReleaseCheckSmokesManualOnlyScheduleRemovalBoundary() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("schedule uninstall --unload"))
        XCTAssertTrue(script.contains("schedule-uninstall-manual.log"))
        XCTAssertTrue(script.contains("will not unload or remove LaunchAgent files automatically"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
