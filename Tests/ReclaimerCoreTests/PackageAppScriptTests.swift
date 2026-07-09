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

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
