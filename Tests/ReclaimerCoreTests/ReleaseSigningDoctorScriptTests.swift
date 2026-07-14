import XCTest

final class ReleaseSigningDoctorScriptTests: XCTestCase {
    private var tempRoot: URL!
    private var toolRoot: URL!
    private var toolLogURL: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiReleaseSigningDoctorTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        toolRoot = tempRoot.appendingPathComponent("tools", isDirectory: true)
        toolLogURL = tempRoot.appendingPathComponent("tool-log.txt")
        try FileManager.default.createDirectory(at: toolRoot, withIntermediateDirectories: true)
        try installFakeTools()
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testDoctorPassesWithDeveloperIDAndReachableNotaryProfileWithoutLeakingSecrets() throws {
        let result = try runDoctor(
            environment: [
                "CODESIGN_IDENTITY": "Developer ID Application: REIDAR OVERREIN JOESSUND (X88J3853S2)",
                "NOTARY_PROFILE": "ryddi-profile",
                "APPLE_APP_PASSWORD": "secret-app-specific-password"
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Developer ID Application identity is available."))
        XCTAssertTrue(result.stdout.contains("Notary profile 'ryddi-profile' is usable."))
        XCTAssertTrue(result.stdout.contains("RYDDI_RELEASE_SIGNING=required"))
        XCTAssertTrue(result.stdout.contains("RYDDI_ARTIFACT_BASENAME=Ryddi-v0.3.1"))
        XCTAssertFalse(result.stdout.contains("secret-app-specific-password"))
        XCTAssertFalse(result.stderr.contains("secret-app-specific-password"))
        XCTAssertTrue(try toolLog().contains("xcrun notarytool history --keychain-profile ryddi-profile --output-format json"))
    }

    func testDoctorFailsWhenNotaryCredentialsAreMissing() throws {
        let result = try runDoctor(
            environment: [
                "CODESIGN_IDENTITY": "Developer ID Application: REIDAR OVERREIN JOESSUND (X88J3853S2)"
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("Notary credentials are missing."))
        XCTAssertTrue(result.stdout.contains("xcrun notarytool store-credentials"))
        XCTAssertTrue(result.stdout.contains("NOTARY_PROFILE"))
    }

    func testDoctorSuggestsOnlyDeveloperIDIdentityWhenCodesignIdentityIsUnset() throws {
        let result = try runDoctor(
            environment: [
                "NOTARY_PROFILE": "ryddi-profile"
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Found one Developer ID Application identity."))
        XCTAssertTrue(result.stdout.contains("CODESIGN_IDENTITY=\"Developer ID Application: REIDAR OVERREIN JOESSUND (X88J3853S2)\""))
    }

    func testDoctorRejectsAppleDevelopmentIdentityForReleaseSigning() throws {
        let result = try runDoctor(
            environment: [
                "CODESIGN_IDENTITY": "Apple Development: reidjoss@gmail.com (835WLRA27M)",
                "NOTARY_PROFILE": "ryddi-profile"
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("CODESIGN_IDENTITY is not a Developer ID Application certificate."))
        XCTAssertFalse(try toolLog().contains("xcrun notarytool history"))
    }

    func testDoctorAcceptsDirectAppleCredentialEnvironmentWithoutPrintingPassword() throws {
        let result = try runDoctor(
            environment: [
                "CODESIGN_IDENTITY": "Developer ID Application: REIDAR OVERREIN JOESSUND (X88J3853S2)",
                "APPLE_ID": "reid@example.invalid",
                "APPLE_TEAM_ID": "X88J3853S2",
                "APPLE_APP_PASSWORD": "direct-secret-password"
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Apple ID notarization environment is present."))
        XCTAssertFalse(result.stdout.contains("direct-secret-password"))
        XCTAssertFalse(result.stderr.contains("direct-secret-password"))
        XCTAssertFalse(try toolLog().contains("xcrun notarytool history"))
    }

    private func runDoctor(environment extraEnvironment: [String: String]) throws -> (status: Int32, stdout: String, stderr: String) {
        try? FileManager.default.removeItem(at: toolLogURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repoRoot().appendingPathComponent("Scripts/release-signing-doctor.sh").path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(toolRoot.path):\(environment["PATH"] ?? "")"
        for key in [
            "CODESIGN_IDENTITY",
            "NOTARY_PROFILE",
            "APPLE_ID",
            "APPLE_TEAM_ID",
            "APPLE_APP_PASSWORD"
        ] {
            environment.removeValue(forKey: key)
        }
        extraEnvironment.forEach { key, value in
            environment[key] = value
        }
        environment["RYDDI_FAKE_TOOL_LOG"] = toolLogURL.path
        process.environment = environment

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

    private func installFakeTools() throws {
        try writeExecutable(
            "security",
            """
            #!/usr/bin/env bash
            set -euo pipefail
            echo "security $*" >> "$RYDDI_FAKE_TOOL_LOG"
            if [[ "$*" == "find-identity -v -p codesigning" ]]; then
              cat <<'OUT'
              1) ABCDEF0123456789ABCDEF0123456789ABCDEF01 "Apple Development: reidjoss@gmail.com (835WLRA27M)"
              2) 1234567890ABCDEF1234567890ABCDEF12345678 "Developer ID Application: REIDAR OVERREIN JOESSUND (X88J3853S2)"
                 2 valid identities found
            OUT
              exit 0
            fi
            exit 2
            """
        )
        try writeExecutable(
            "xcrun",
            """
            #!/usr/bin/env bash
            set -euo pipefail
            echo "xcrun $*" >> "$RYDDI_FAKE_TOOL_LOG"
            if [[ "$1" == "notarytool" && "$2" == "history" ]]; then
              printf '{"history":[]}\\n'
              exit 0
            fi
            exit 2
            """
        )
    }

    private func writeExecutable(_ name: String, _ contents: String) throws {
        let url = toolRoot.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func toolLog() throws -> String {
        guard FileManager.default.fileExists(atPath: toolLogURL.path) else {
            return ""
        }
        return try String(contentsOf: toolLogURL, encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
