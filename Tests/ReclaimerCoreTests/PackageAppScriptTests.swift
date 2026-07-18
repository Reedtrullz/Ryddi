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

    func testPackageAppDefaultsToV040GuidedMapRelease() throws {
        let root = repoRoot()
        let script = try String(contentsOf: root.appendingPathComponent("Scripts/package-app.sh"), encoding: .utf8)
        let signingDoctor = try String(contentsOf: root.appendingPathComponent("Scripts/release-signing-doctor.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("bundle_version=\"${RYDDI_VERSION:-0.4.0}\""))
        XCTAssertTrue(script.contains("bundle_build=\"${RYDDI_BUILD_NUMBER:-5}\""))
        XCTAssertTrue(signingDoctor.contains("RYDDI_ARTIFACT_BASENAME:-Ryddi-v0.4.0"))
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
        XCTAssertTrue(script.contains("-insert sourceDirty -string \"$source_dirty\" \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("-insert buildDate -string \"$build_date\" \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("-convert json -o \"$build_metadata\" \"$build_metadata_plist\""))
        XCTAssertTrue(script.contains("rm \"$build_metadata_plist\""))

        let metadataWrite = try XCTUnwrap(script.range(of: "Ryddi-build.json"))
        let signing = try XCTUnwrap(script.range(of: "codesign --force"))
        XCTAssertLessThan(metadataWrite.lowerBound, signing.lowerBound)
    }

    func testPackageAppEmbedsIconBeforeSigning() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/package-app.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("Assets/Ryddi.icns"))
        XCTAssertTrue(script.contains("$app/Contents/Resources/Ryddi.icns"))
        XCTAssertTrue(script.contains("<key>CFBundleIconFile</key>"))
        XCTAssertTrue(script.contains("<string>Ryddi</string>"))
        let iconCopy = try XCTUnwrap(script.range(of: "cp \"$icon\""))
        let signing = try XCTUnwrap(script.range(of: "codesign --force"))
        XCTAssertLessThan(iconCopy.lowerBound, signing.lowerBound)
    }

    func testPackageAppEmbedsSecureSparkleConfigurationAndFramework() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/package-app.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("Contents/Frameworks/Sparkle.framework"))
        XCTAssertTrue(script.contains("<key>SUFeedURL</key>"))
        XCTAssertTrue(script.contains("https://raw.githubusercontent.com/Reedtrullz/Ryddi/main/appcast.xml"))
        XCTAssertTrue(script.contains("<key>SUPublicEDKey</key>"))
        XCTAssertTrue(script.contains("<key>SUEnableAutomaticChecks</key>"))
        XCTAssertTrue(script.contains("<key>SUAutomaticallyUpdate</key>"))
        XCTAssertTrue(script.contains("<key>SUVerifyUpdateBeforeExtraction</key>"))
        XCTAssertTrue(script.contains("<key>SURequireSignedFeed</key>"))
    }

    func testReleaseCheckCreatesDedicatedSparkleUpdateArchive() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("update_zip_path=\"$dist/$artifact_basename-update.zip\""))
        XCTAssertTrue(script.contains("/usr/bin/ditto -c -k --keepParent \"$app\" \"$update_zip_path\""))
        XCTAssertTrue(script.contains("sparkle_update_archive=\"notarized-signed-app-only\""))
    }

    func testAppcastGeneratorSignsFeedWithoutEmbeddingPrivateKey() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/generate-appcast.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("RYDDI_SPARKLE_KEY_ACCOUNT:-ed25519"))
        XCTAssertTrue(script.contains("--download-url-prefix \"https://github.com/Reedtrullz/Ryddi/releases/download/v$version/\""))
        XCTAssertTrue(script.contains("--verify \"$scratch/appcast.xml\""))
        XCTAssertTrue(script.contains("sparkle:edSignature="))
        XCTAssertTrue(script.contains("<!-- sparkle-signatures:"))
        XCTAssertTrue(script.contains("printf '%s' \"$private_key\" |"))
        XCTAssertTrue(script.contains("--ed-key-file -"))
        XCTAssertFalse(script.contains(" -s \"$private_key\""))
    }

    func testPackageSignsNestedCLIThenAppWithoutDeepSigning() throws {
        let root = repoRoot()
        let script = try String(
            contentsOf: root.appendingPathComponent("Scripts/package-app.sh"),
            encoding: .utf8
        )
        let releaseCheck = try String(
            contentsOf: root.appendingPathComponent("Scripts/release-check.sh"),
            encoding: .utf8
        )
        let nestedSignCommand = "codesign --force --options runtime --timestamp --sign \"$CODESIGN_IDENTITY\" \"$app/Contents/MacOS/reclaimer\""
        let appSignCommand = "codesign --force --options runtime --timestamp --sign \"$CODESIGN_IDENTITY\" \"$app\""
        let nestedVerifyCommand = "codesign --verify --strict --verbose=2 \"$app/Contents/MacOS/reclaimer\""
        let appVerifyCommand = "codesign --verify --deep --strict --verbose=2 \"$app\""

        XCTAssertFalse(script.contains("codesign --force --deep"))
        let nestedSign = try XCTUnwrap(script.range(of: nestedSignCommand))
        let appSign = try XCTUnwrap(script.range(of: appSignCommand))
        let nestedVerify = try XCTUnwrap(script.range(of: nestedVerifyCommand))
        let appVerify = try XCTUnwrap(script.range(of: appVerifyCommand))
        XCTAssertLessThan(nestedSign.lowerBound, appSign.lowerBound)
        XCTAssertLessThan(appSign.lowerBound, nestedVerify.lowerBound)
        XCTAssertLessThan(nestedVerify.lowerBound, appVerify.lowerBound)
        XCTAssertTrue(releaseCheck.contains(nestedVerifyCommand))
        XCTAssertTrue(releaseCheck.contains(appVerifyCommand))
    }

    func testIconGeneratorAndRequiredRepresentationsExist() throws {
        let root = repoRoot()
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Scripts/generate-app-icon.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Assets/Ryddi.icns").path))
        for name in [
            "icon_16x16.png", "icon_16x16@2x.png",
            "icon_32x32.png", "icon_32x32@2x.png",
            "icon_128x128.png", "icon_128x128@2x.png",
            "icon_256x256.png", "icon_256x256@2x.png",
            "icon_512x512.png", "icon_512x512@2x.png"
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent("Assets/AppIcon.iconset/\(name)").path),
                name
            )
        }
    }

    func testReleaseCheckHidesBuildDirectoryForPackagedCliSmokes() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(
            script.contains("hide_build_dir_for_packaged_smokes"),
            "release-check must hide .build before packaged CLI smokes so Bundle.module build-path fallback cannot mask packaging bugs."
        )
    }

    func testReleaseCheckDefaultsSignedArtifactsToV040GuidedMapRelease() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("release_version=\"${RYDDI_VERSION:-0.4.0}\""))
        XCTAssertTrue(script.contains("release_build=\"${RYDDI_BUILD_NUMBER:-5}\""))
        XCTAssertTrue(script.contains("artifact_basename=\"Ryddi-v$release_version\""))
        XCTAssertTrue(script.contains("artifact_basename=\"Ryddi-developer-preview\""))
    }

    func testSignedWorkflowRequiresExactVersionTagAndCleanCommitBeforeCredentials() throws {
        let workflow = try String(
            contentsOf: repoRoot().appendingPathComponent(".github/workflows/release-preview.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(workflow.contains("[[ \"$RYDDI_VERSION\" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+$ ]]"))
        XCTAssertTrue(workflow.contains("[[ \"$RYDDI_BUILD_NUMBER\" =~ ^[1-9][0-9]*$ ]]"))
        XCTAssertTrue(workflow.contains("test \"$RELEASE_REF\" = \"v$RYDDI_VERSION\""))
        XCTAssertTrue(workflow.contains("git rev-parse \"$RELEASE_REF^{commit}\""))
        XCTAssertTrue(workflow.contains("git status --porcelain --untracked-files=normal"))

        let provenance = try XCTUnwrap(workflow.range(of: "Verify immutable release provenance"))
        let credentials = try XCTUnwrap(workflow.range(of: "Import Developer ID certificate"))
        XCTAssertLessThan(provenance.lowerBound, credentials.lowerBound)
    }

    func testReleaseCheckCapturesSourceProvenanceBeforeHidingBuildDirectory() throws {
        let script = try String(
            contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"),
            encoding: .utf8
        )

        let sourceCapture = try XCTUnwrap(script.range(of: "source_dirty=$([["))
        let hideBuildDirectory = try XCTUnwrap(script.range(of: "\nhide_build_dir_for_packaged_smokes\n"))

        XCTAssertLessThan(sourceCapture.lowerBound, hideBuildDirectory.lowerBound)
        XCTAssertTrue(script.contains("if [[ \"$source_dirty\" != \"false\" ]]; then"))
        XCTAssertTrue(script.contains(#"RYDDI_SOURCE_COMMIT="$commit" \"#))
        XCTAssertTrue(script.contains(#"RYDDI_SOURCE_DIRTY="$source_dirty" \"#))
    }

    func testReleaseCheckStagesProofBesideAppBeforeZippingDirectory() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("stage_dir=\"$dist/$artifact_basename\""))
        XCTAssertTrue(script.contains("$stage_dir/Ryddi.app"))
        XCTAssertTrue(script.contains("$stage_dir/Ryddi-release-manifest.txt"))
        XCTAssertTrue(script.contains("$stage_dir/Ryddi-checksums.sha256"))
        XCTAssertTrue(script.contains("archive_staged_release"))
    }

    func testReleaseChecksumsUseRealPortableBasenames() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("shasum -a 256 \"$(basename \"$zip_path\")\""))
        XCTAssertTrue(script.contains("shasum -a 256 \"Ryddi-release-manifest.txt\""))
        XCTAssertFalse(script.contains("\"$app_payload_sha\" \"Ryddi.app\""))
        XCTAssertTrue(script.contains("assert_public_file_has_no_local_paths \"$checksum_path\""))
    }

    func testSignedReleaseRequiresCleanSourceAndWorkflowCleansCredentials() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)
        let workflow = try String(contentsOf: repoRoot().appendingPathComponent(".github/workflows/release-preview.yml"), encoding: .utf8)

        XCTAssertTrue(script.contains("signed releases require a clean Git worktree"))
        XCTAssertTrue(workflow.contains("Verify immutable release provenance"))
        XCTAssertTrue(workflow.contains("test \"$RELEASE_REF\" = \"v$RYDDI_VERSION\""))
        XCTAssertTrue(workflow.contains("git rev-parse \"$RELEASE_REF^{commit}\""))
        XCTAssertTrue(workflow.contains("if: ${{ always() }}"))
        XCTAssertTrue(workflow.contains("rm -f \"$p12\""))
        XCTAssertTrue(workflow.contains("security delete-keychain \"$keychain\""))
        XCTAssertFalse(workflow.contains("uses: actions/checkout@v4"))
        XCTAssertFalse(workflow.contains("uses: actions/upload-artifact@v4"))
    }

    func testReleaseManifestCarriesExactTrustEvidenceFields() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        for field in [
            "version=$bundle_version",
            "build=$bundle_build",
            "source_commit=$commit",
            "source_dirty=$source_dirty",
            "signing_identity=$signing_identity",
            "notarization_submission_id=$notary_submission",
            "notarization_status=$notarization_status",
            "stapler_validated=$stapler_validated",
            "gatekeeper=$gatekeeper_status",
            "packaged_ax_e2e=$packaged_ax_e2e_status",
            "packaged_ax_e2e_proof=",
            "sha256=$app_payload_sha",
        ] {
            XCTAssertTrue(script.contains(field), "Missing manifest field: \(field)")
        }
    }

    func testReleaseCheckIncludesPackagedAccessibilityProofOnlyAfterPassingGate() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("Scripts/release-check.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("RYDDI_REQUIRE_PACKAGED_AX_E2E"))
        XCTAssertTrue(script.contains("packaged_ax_e2e_status=\"passed\""))
        XCTAssertTrue(script.contains("$stage_dir/Packaged-App-E2E"))
        XCTAssertTrue(script.contains(".trashArtifactCleaned == true"))
    }

    func testReleaseWorkflowUploadsStagedDirectoryArtifactAndKeepsPreviewUnsigned() throws {
        let workflow = try String(contentsOf: repoRoot().appendingPathComponent(".github/workflows/release-preview.yml"), encoding: .utf8)

        XCTAssertTrue(workflow.contains("Build unsigned developer preview"))
        XCTAssertTrue(workflow.contains("name: Ryddi-developer-preview"))
        XCTAssertTrue(workflow.contains("dist/Ryddi-developer-preview.zip"))
        XCTAssertTrue(workflow.contains("dist/Ryddi-v${{ inputs.version }}.zip"))
        XCTAssertTrue(workflow.contains("runs-on: [self-hosted, macOS, ryddi-release]"))
        XCTAssertTrue(workflow.contains("RYDDI_REQUIRE_PACKAGED_AX_E2E: \"1\""))
        XCTAssertTrue(workflow.contains("dist/e2e-proof"))
        XCTAssertFalse(workflow.contains("NOTARY_PROFILE: ${{ secrets.NOTARY_PROFILE }}"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
