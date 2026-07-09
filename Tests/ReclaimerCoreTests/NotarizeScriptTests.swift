import XCTest

final class NotarizeScriptTests: XCTestCase {
    private var tempRoot: URL!
    private var toolRoot: URL!
    private var appURL: URL!
    private var toolLogURL: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiNotarizeScriptTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        toolRoot = tempRoot.appendingPathComponent("tools", isDirectory: true)
        appURL = tempRoot.appendingPathComponent("dist/Ryddi.app", isDirectory: true)
        toolLogURL = tempRoot.appendingPathComponent("tool-log.txt")
        try FileManager.default.createDirectory(at: toolRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try installFakeTools()
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testNotarizeAcceptedRecordsStatusAndValidatesStapledApp() throws {
        let result = try runNotarize(mode: "accepted")

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(try file("dist/Ryddi-notary-status.json").contains("\"status\":\"Accepted\""))
        let toolLog = try String(contentsOf: toolLogURL, encoding: .utf8)
        XCTAssertTrue(toolLog.contains("xcrun notarytool submit"))
        XCTAssertTrue(toolLog.contains("xcrun stapler staple"))
        XCTAssertTrue(toolLog.contains("spctl --assess --type execute --verbose"))
        XCTAssertTrue(toolLog.contains("codesign --verify --deep --strict --verbose=2"))
    }

    func testNotarizePendingTimeoutExitsWithResumeCommandAndDoesNotStaple() throws {
        let result = try runNotarize(mode: "pending")

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("RYDDI_NOTARY_SUBMISSION_ID=fixture-submission"))
        XCTAssertTrue(try file("dist/Ryddi-notary-status.json").contains("\"status\":\"In Progress\""))
        let toolLog = try String(contentsOf: toolLogURL, encoding: .utf8)
        XCTAssertFalse(toolLog.contains("xcrun stapler staple"))
    }

    func testNotarizeResumeAcceptedSkipsSubmitAndStaples() throws {
        let result = try runNotarize(mode: "accepted", resumeID: "resume-submission")

        XCTAssertEqual(result.status, 0, result.stderr)
        let toolLog = try String(contentsOf: toolLogURL, encoding: .utf8)
        XCTAssertFalse(toolLog.contains("xcrun notarytool submit"))
        XCTAssertTrue(toolLog.contains("xcrun notarytool wait resume-submission"))
        XCTAssertTrue(toolLog.contains("xcrun stapler validate"))
    }

    func testNotarizeInvalidFetchesLogAndFails() throws {
        let result = try runNotarize(mode: "invalid")

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(try file("dist/Ryddi-notary-log.json").contains("fixture invalid"))
        let toolLog = try String(contentsOf: toolLogURL, encoding: .utf8)
        XCTAssertFalse(toolLog.contains("xcrun stapler staple"))
    }

    private func runNotarize(mode: String, resumeID: String? = nil) throws -> (status: Int32, stdout: String, stderr: String) {
        try? FileManager.default.removeItem(at: toolLogURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repoRoot().appendingPathComponent("Scripts/notarize-app.sh").path, appURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(toolRoot.path):\(environment["PATH"] ?? "")"
        environment["NOTARY_PROFILE"] = "fixture-profile"
        environment["RYDDI_FAKE_NOTARY_MODE"] = mode
        environment["RYDDI_FAKE_TOOL_LOG"] = toolLogURL.path
        environment["RYDDI_NOTARY_WAIT_TIMEOUT"] = "1s"
        if let resumeID {
            environment["RYDDI_NOTARY_SUBMISSION_ID"] = resumeID
        }
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
            "ditto",
            """
            #!/usr/bin/env bash
            set -euo pipefail
            echo "ditto $*" >> "$RYDDI_FAKE_TOOL_LOG"
            output="${@: -1}"
            mkdir -p "$(dirname "$output")"
            printf 'zip fixture\\n' > "$output"
            """
        )
        try writeExecutable(
            "xcrun",
            """
            #!/usr/bin/env bash
            set -euo pipefail
            echo "xcrun $*" >> "$RYDDI_FAKE_TOOL_LOG"
            if [[ "$1" == "stapler" ]]; then
              exit 0
            fi
            if [[ "$1" != "notarytool" ]]; then
              exit 2
            fi
            command="$2"
            mode="${RYDDI_FAKE_NOTARY_MODE:-accepted}"
            case "$command" in
              submit)
                printf '{"id":"fixture-submission","status":"In Progress"}\\n'
                ;;
              wait)
                submission="$3"
                case "$mode" in
                  accepted)
                    printf '{"id":"%s","status":"Accepted"}\\n' "$submission"
                    ;;
                  pending)
                    printf '{"id":"%s","status":"In Progress"}\\n' "$submission"
                    exit 75
                    ;;
                  invalid)
                    printf '{"id":"%s","status":"Invalid"}\\n' "$submission"
                    exit 1
                    ;;
                esac
                ;;
              log)
                printf '{"issues":[{"message":"fixture invalid"}]}\\n'
                ;;
              *)
                exit 2
                ;;
            esac
            """
        )
        try writeExecutable(
            "spctl",
            """
            #!/usr/bin/env bash
            set -euo pipefail
            echo "spctl $*" >> "$RYDDI_FAKE_TOOL_LOG"
            """
        )
        try writeExecutable(
            "codesign",
            """
            #!/usr/bin/env bash
            set -euo pipefail
            echo "codesign $*" >> "$RYDDI_FAKE_TOOL_LOG"
            """
        )
    }

    private func writeExecutable(_ name: String, _ contents: String) throws {
        let url = toolRoot.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func file(_ relativePath: String) throws -> String {
        try String(contentsOf: tempRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
