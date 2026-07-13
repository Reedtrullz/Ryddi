import XCTest
@testable import ReclaimerCore

final class NativeExecutableResolverTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiNativeResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testResolverAcceptsExecutableOnlyInsideApprovedVersionedNodeRoot() throws {
        let bin = tempRoot.appendingPathComponent(".nvm/versions/node/v20/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent("npm")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let resolution = try SystemNativeExecutableResolver(path: bin.path, homeDirectory: tempRoot).resolve("npm")

        XCTAssertEqual(resolution.launchPath, executable.path)
        XCTAssertEqual(resolution.resolvedPath, executable.path)
        XCTAssertTrue(resolution.identity?.isRegularFile == true)
    }

    func testResolverRejectsExecutableFromArbitraryPathEntry() throws {
        let bin = tempRoot.appendingPathComponent("unapproved", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent("brew")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        XCTAssertThrowsError(try SystemNativeExecutableResolver(path: bin.path, homeDirectory: tempRoot).resolve("brew")) { error in
            XCTAssertEqual(error as? NativeExecutableResolutionError, .unavailable("brew"))
        }
    }

    func testProcessRunnerExecutesAbsolutePathWithoutEnvLookup() {
        let output = ProcessToolCommandRunner().run(
            ToolCommandInvocation(executable: "/usr/bin/printf", arguments: ["absolute-path-proof"]),
            timeout: 2
        )

        XCTAssertTrue(output.succeeded, output.launchError ?? output.stderr)
        XCTAssertEqual(output.stdout, "absolute-path-proof")
    }

    func testProcessRunnerFailsClosedForUnresolvedBareExecutable() {
        let output = ProcessToolCommandRunner().run(
            ToolCommandInvocation(executable: "ryddi-tool-that-does-not-exist", arguments: []),
            timeout: 2
        )

        XCTAssertFalse(output.succeeded)
        XCTAssertNil(output.exitCode)
        XCTAssertTrue(output.launchError?.localizedCaseInsensitiveContains("approved") ?? false)
        XCTAssertFalse(output.stdout.contains("unsafe"))
    }

    func testProcessRunnerRejectsAbsoluteExecutableOutsideApprovedRoots() throws {
        let executable = tempRoot.appendingPathComponent("brew")
        try "#!/bin/sh\necho unsafe\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let output = ProcessToolCommandRunner().run(
            ToolCommandInvocation(executable: executable.path, arguments: ["cleanup", "--dry-run"]),
            timeout: 2
        )

        XCTAssertFalse(output.succeeded)
        XCTAssertNil(output.exitCode)
        XCTAssertTrue(output.launchError?.localizedCaseInsensitiveContains("outside approved") ?? false)
        XCTAssertFalse(output.stdout.contains("unsafe"))
    }
}
