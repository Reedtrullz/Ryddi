import XCTest

final class PackageAppScriptTests: XCTestCase {
    func testPackageAppKeepsResourceBundleInsideSignedAppResources() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/package-app.sh"), encoding: .utf8)

        XCTAssertTrue(
            script.contains("conventional_resource_bundle=\"$app/Contents/Resources/$(basename \"$selected_resource_bundle\")\""),
            "Resource bundles must stay inside Contents/Resources so the app remains signable."
        )
        XCTAssertFalse(
            script.contains("swiftpm_resource_bundle=\"$app/"),
            "Root-level bundle contents make codesign fail with unsealed contents in the bundle root."
        )
    }

    func testPackageAppDefaultsToCurrentReleaseVersion() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/package-app.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("bundle_version=\"${RYDDI_VERSION:-0.3.0}\""))
        XCTAssertTrue(script.contains("bundle_build=\"${RYDDI_BUILD_NUMBER:-3}\""))
    }

    func testPackageAppWritesEmbeddedBuildMetadataBeforeSigning() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/package-app.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("Ryddi-build.json"))
        XCTAssertTrue(script.contains("source_commit="))
        XCTAssertTrue(script.contains("build_date="))
        XCTAssertTrue(script.contains("-create xml1 \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("-insert version -string \"$bundle_version\" \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("-insert build -string \"$bundle_build\" \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("-insert sourceCommit -string \"$source_commit\" \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("-insert buildDate -string \"$build_date\" \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("-convert json -o \"$build_metadata\" \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("rm \"$build_metadata_plist\""))

        let metadataWrite = try XCTUnwrap(script.range(of: "Ryddi-build.json"))
        let signing = try XCTUnwrap(script.range(of: "codesign --force"))
        XCTAssertLessThan(metadataWrite.lowerBound, signing.lowerBound)
    }

    func testReleaseCheckHidesBuildDirectoryForPackagedCliSmokes() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(
            script.contains("hide_build_dir_for_packaged_smokes"),
            "release-check must hide .build before packaged CLI smokes so Bundle.module build-path fallback cannot mask packaging bugs."
        )
    }

    func testReleaseCheckDefaultsSignedArtifactsToCurrentRelease() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("release_version=\"${RYDDI_VERSION:-0.3.0}\""))
        XCTAssertTrue(script.contains("release_build=\"${RYDDI_BUILD_NUMBER:-3}\""))
        XCTAssertTrue(script.contains("artifact_basename=\"Ryddi-v$release_version\""))
        XCTAssertTrue(script.contains("artifact_basename=\"Ryddi-developer-preview\""))
    }

    func testReleaseCheckStagesProofBesideAppBeforeZippingDirectory() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("stage_dir=\"$dist/$artifact_basename\""))
        XCTAssertTrue(script.contains("$stage_dir/Ryddi.app"))
        XCTAssertTrue(script.contains("$stage_dir/Ryddi-release-manifest.txt"))
        XCTAssertTrue(script.contains("$stage_dir/Ryddi-checksums.sha256"))
        XCTAssertTrue(script.contains("archive_staged_release"))
    }

    func testReleaseManifestCarriesExactTrustEvidenceFields() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        for field in [
            "version=$bundle_version",
            "build=$bundle_build",
            "source_commit=$commit",
            "signing_identity=$signing_identity",
            "notarization_submission_id=$notary_submission",
            "notarization_status=$notarization_status",
            "stapler_validated=$stapler_validated",
            "gatekeeper=$gatekeeper_status",
            "sha256=$app_payload_sha",
        ] {
            XCTAssertTrue(script.contains(field), "Missing manifest field: \(field)")
        }
    }

    func testReleaseWorkflowUploadsStagedDirectoryArtifactAndKeepsPreviewUnsigned() throws {
        let workflow = try String(contentsOf: repoRoot().appendingPathComponent(".github/workflows/release-preview.yml"), encoding: .utf8)

        XCTAssertTrue(workflow.contains("Build unsigned developer preview"))
        XCTAssertTrue(workflow.contains("name: Ryddi-developer-preview"))
        XCTAssertTrue(workflow.contains("dist/Ryddi-developer-preview.zip"))
        XCTAssertTrue(workflow.contains("dist/Ryddi-v0.3.0.zip"))
        XCTAssertFalse(workflow.contains("NOTARY_PROFILE: ${{ secrets.NOTARY_PROFILE }}"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
