import XCTest

final class AppE2EFixtureTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiAppE2EFixtureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testFixtureScriptCreatesBoundedSafetyMatrixWithoutRealHomePaths() throws {
        let fixture = tempRoot.appendingPathComponent("fixture", isDirectory: true)
        let result = try runFixtureScript(root: fixture)

        XCTAssertEqual(result.status, 0, result.stderr)
        let requiredRelativePaths = [
            ".ryddi-e2e-fixture",
            "Library/Caches/Codex/cache.bin",
            "Downloads/large-review.bin",
            "Library/Application Support/Google/Chrome/Default/Login Data",
            ".codex/sessions/e2e-session.jsonl",
            "Library/Caches/Codex/symlink-candidate",
            "Applications/Ryddi E2E Fixture.app/Contents/Info.plist",
            "Applications/Ryddi E2E Fixture.app/Contents/MacOS/RyddiE2EFixture"
        ]
        for relativePath in requiredRelativePaths {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fixture.appendingPathComponent(relativePath).path),
                "Missing E2E fixture path: \(relativePath)"
            )
        }
        let symlink = fixture.appendingPathComponent("Library/Caches/Codex/symlink-candidate")
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path))

        let fixturePrefix = fixture.standardizedFileURL.path + "/"
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: fixture,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
        )
        for case let item as URL in enumerator {
            XCTAssertTrue(item.standardizedFileURL.path.hasPrefix(fixturePrefix), item.path)
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let data = try Data(contentsOf: item)
            guard let text = String(data: data, encoding: .utf8) else { continue }
            XCTAssertFalse(text.contains(FileManager.default.homeDirectoryForCurrentUser.path), item.path)
            XCTAssertFalse(text.contains("/Users/reidar"), item.path)
        }
    }

    func testFixtureScriptRejectsUnsafeRootsWithoutMutation() throws {
        for unsafeRoot in [
            URL(fileURLWithPath: "/"),
            FileManager.default.homeDirectoryForCurrentUser
        ] {
            let result = try runFixtureScript(root: unsafeRoot)
            XCTAssertNotEqual(result.status, 0)
            XCTAssertTrue(result.stderr.localizedCaseInsensitiveContains("unsafe"), result.stderr)
        }
    }

    func testSmokeScriptAndReleaseGatesUseDisposableFixtureProof() throws {
        let root = repoRoot()
        let smoke = try String(
            contentsOf: root.appendingPathComponent("Scripts/app-e2e-smoke.sh"),
            encoding: .utf8
        )
        let releaseCheck = try String(
            contentsOf: root.appendingPathComponent("Scripts/release-check.sh"),
            encoding: .utf8
        )
        let packagedAX = try String(
            contentsOf: root.appendingPathComponent("Scripts/run-packaged-app-e2e.sh"),
            encoding: .utf8
        )
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let releaseWorkflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release-preview.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(smoke.contains("mktemp -d"))
        XCTAssertTrue(smoke.contains("trap cleanup EXIT"))
        XCTAssertTrue(smoke.contains("RYDDI_E2E_MODE=1"))
        XCTAssertTrue(smoke.contains("RYDDI_E2E_SCOPE_ROOT=\"$fixture\""))
        XCTAssertTrue(smoke.contains("screencapture -x -o -l \"$window_id\""))
        XCTAssertTrue(smoke.contains("run_cli scan"))
        XCTAssertTrue(smoke.contains("run_cli plan"))
        XCTAssertTrue(smoke.contains("run_cli execute --dry-run"))
        XCTAssertTrue(smoke.contains("run_cli apps uninstall"))
        XCTAssertTrue(smoke.contains("protected-preserved=yes"))
        XCTAssertTrue(smoke.contains("RYDDI_E2E_MIN_FREE_GIB:-30"))
        XCTAssertTrue(releaseCheck.contains("RYDDI_E2E_APP_PATH=\"$app\""))
        XCTAssertTrue(releaseCheck.contains("Scripts/app-e2e-smoke.sh"))
        XCTAssertTrue(releaseCheck.contains("RYDDI_REQUIRE_PACKAGED_AX_E2E"))
        XCTAssertTrue(releaseCheck.contains("Scripts/run-packaged-app-e2e.sh"))
        XCTAssertTrue(releaseCheck.contains("packaged_ax_e2e=$packaged_ax_e2e_status"))
        XCTAssertTrue(packagedAX.contains("if [[ -z \"${RYDDI_E2E_APP_PATH:-}\" ]]"))
        XCTAssertTrue(packagedAX.contains("\"$root/Scripts/package-app.sh\""))
        XCTAssertTrue(packagedAX.contains("$HOME/.Trash/"))
        XCTAssertTrue(packagedAX.contains("Refusing to clean an E2E Trash artifact without bounded receipt evidence."))
        XCTAssertTrue(packagedAX.contains("trashArtifactCleaned"))
        let harness = try String(
            contentsOf: root.appendingPathComponent("Tests/AppE2E/RyddiAXHarness.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(harness.contains("home.primary-action"))
        XCTAssertTrue(harness.contains("cleanup-review.select-safe"))
        XCTAssertTrue(harness.contains("cleanup-review.check-safely"))
        XCTAssertTrue(harness.contains("cleanup-review.move-to-trash"))
        XCTAssertTrue(harness.contains("home.suggestion.home-suggestion:safeMaintenance"))
        XCTAssertTrue(harness.contains("Safe maintenance scoped review title"))
        XCTAssertTrue(harness.contains("assertEmptyCleanupSelection"))
        XCTAssertTrue(harness.contains("Empty cleanup selection"))
        XCTAssertTrue(harness.contains("Explore Tools segment"))
        XCTAssertFalse(harness.contains("explore.mode.tools"))
        XCTAssertFalse(harness.contains("as! AXUIElement"))
        XCTAssertTrue(harness.contains("CFGetTypeID(value) == AXUIElementGetTypeID()"))
        XCTAssertFalse(harness.contains("queue.removeFirst()"))
        XCTAssertTrue(ci.contains("Fixture-backed app E2E smoke"))
        XCTAssertTrue(ci.contains("timeout-minutes: 10"))
        XCTAssertTrue(ci.contains("RYDDI_E2E_MIN_FREE_GIB: \"5\""))
        XCTAssertTrue(releaseWorkflow.contains("RYDDI_E2E_MIN_FREE_GIB: \"5\""))
    }

    func testPackagedAXHarnessKeepsReclaimBlockedAfterFreshVerificationScan() throws {
        let root = repoRoot()
        let harness = try String(
            contentsOf: root.appendingPathComponent("Tests/AppE2E/RyddiAXHarness.swift"),
            encoding: .utf8
        )
        let packagedAX = try String(
            contentsOf: root.appendingPathComponent("Scripts/run-packaged-app-e2e.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(harness.contains("try press(\"home.primary-action\", root: app)"))
        XCTAssertTrue(harness.contains("try waitForVerificationScanCompletion(root: app"))
        XCTAssertTrue(harness.contains("reclaimActionHiddenAfterVerificationScan: true"))
        XCTAssertTrue(packagedAX.contains(".reclaimActionHiddenAfterVerificationScan == true"))
    }

    func testPackagedAXHarnessProvesCancellationAndCurrentCleanupFlow() throws {
        let root = repoRoot()
        let harness = try String(
            contentsOf: root.appendingPathComponent("Tests/AppE2E/RyddiAXHarness.swift"),
            encoding: .utf8
        )
        let packagedAX = try String(
            contentsOf: root.appendingPathComponent("Scripts/run-packaged-app-e2e.sh"),
            encoding: .utf8
        )
        let releaseCheck = try String(
            contentsOf: root.appendingPathComponent("Scripts/release-check.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(harness.contains("waitForElement(identifier: \"scan-progress\""))
        XCTAssertTrue(harness.contains("try press(\"cancel-scan-button\", root: app)"))
        XCTAssertTrue(harness.contains("waitForCancelledScanToBecomeIdle"))
        XCTAssertTrue(harness.contains("assertNoLateCancelledScanCommit"))
        for proof in [
            "scanProgressVisible: true",
            "cancelledScanBecameIdle: true",
            "cancelledScanHadNoLateCommit: true",
            "normalScanCompleted: true",
            "candidateRowRemoved: true",
            "verificationActionVisible: true"
        ] {
            XCTAssertTrue(harness.contains(proof), proof)
        }
        XCTAssertTrue(packagedAX.contains("RYDDI_E2E_SCAN_DELAY_MILLISECONDS=\"750\""))
        XCTAssertTrue(packagedAX.contains(".scanProgressVisible == true"))
        XCTAssertTrue(packagedAX.contains(".cancelledScanBecameIdle == true"))
        XCTAssertTrue(packagedAX.contains(".cancelledScanHadNoLateCommit == true"))
        XCTAssertTrue(packagedAX.contains(".normalScanCompleted == true"))
        XCTAssertTrue(packagedAX.contains("protectedFixtureIntact: true"))
        XCTAssertTrue(releaseCheck.contains(".protectedFixtureIntact == true"))
    }

    private func runFixtureScript(root: URL) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            repoRoot().appendingPathComponent("Scripts/make-app-e2e-fixture.sh").path,
            root.path
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
