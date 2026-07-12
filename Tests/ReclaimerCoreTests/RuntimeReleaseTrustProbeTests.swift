import Foundation
import XCTest
@testable import ReclaimerCore

final class RuntimeReleaseTrustProbeTests: XCTestCase {
    func testUnsignedCodeIsReportedWithoutTrustClaim() throws {
        let fixture = try Fixture()
        let runner = FakeRunner(outputs: [
            output("/usr/bin/codesign", verifyArguments(fixture.appURL), exitCode: 1, stderr: "code object is not signed at all"),
            output("/usr/sbin/spctl", gatekeeperArguments(fixture.appURL), exitCode: 3, stderr: "rejected")
        ])

        let report = makeProbe(runner: runner).inspect(appURL: fixture.appURL)

        XCTAssertEqual(report.signature.state, .unsigned)
        XCTAssertFalse(report.claims.contains("Developer ID signed"))
    }

    func testValidDeveloperIDSignatureIsDistinguished() throws {
        let fixture = try Fixture()
        let runner = FakeRunner(outputs: signedOutputs(for: fixture.appURL) + [
            output("/usr/sbin/spctl", gatekeeperArguments(fixture.appURL), exitCode: 3, stderr: "rejected")
        ])

        let report = makeProbe(runner: runner).inspect(appURL: fixture.appURL)

        XCTAssertEqual(report.signature.state, .developerIDSigned)
        XCTAssertEqual(report.signature.label, "Developer ID signed")
        XCTAssertTrue(report.claims.contains("Developer ID signed"))
    }

    func testGatekeeperAcceptanceIsReportedAsLocalFactOnly() throws {
        let fixture = try Fixture()
        let runner = FakeRunner(outputs: signedOutputs(for: fixture.appURL) + [
            output(
                "/usr/sbin/spctl",
                gatekeeperArguments(fixture.appURL),
                stderr: "Ryddi.app: accepted\nsource=Notarized Developer ID"
            )
        ])

        let report = makeProbe(runner: runner).inspect(appURL: fixture.appURL)

        XCTAssertEqual(report.gatekeeper.state, .gatekeeperAccepted)
        XCTAssertEqual(report.gatekeeper.label, "Gatekeeper accepted")
        XCTAssertTrue(report.claims.contains("Gatekeeper accepted"))
        XCTAssertFalse(report.claims.contains { $0.localizedCaseInsensitiveContains("notarized") })
        XCTAssertFalse(report.claims.contains { $0.localizedCaseInsensitiveContains("stapled") })
    }

    func testUnnotarizedDeveloperIDRejectionIsDistinguished() throws {
        let fixture = try Fixture()
        let runner = FakeRunner(outputs: signedOutputs(for: fixture.appURL) + [
            output(
                "/usr/sbin/spctl",
                gatekeeperArguments(fixture.appURL),
                exitCode: 3,
                stderr: "Ryddi.app: rejected\nsource=Unnotarized Developer ID"
            )
        ])

        let report = makeProbe(runner: runner).inspect(appURL: fixture.appURL)

        XCTAssertEqual(report.gatekeeper.state, .gatekeeperRejectedUnnotarized)
        XCTAssertEqual(report.gatekeeper.label, "Gatekeeper rejected: unnotarized")
    }

    func testUnavailableToolsProduceUnableToVerifyStates() throws {
        let fixture = try Fixture()
        let runner = FakeRunner(outputs: [
            ToolCommandOutput(
                invocation: invocation("/usr/bin/codesign", verifyArguments(fixture.appURL)),
                exitCode: nil,
                launchError: "tool unavailable"
            ),
            ToolCommandOutput(
                invocation: invocation("/usr/sbin/spctl", gatekeeperArguments(fixture.appURL)),
                exitCode: nil,
                timedOut: true
            )
        ])

        let report = makeProbe(runner: runner).inspect(appURL: fixture.appURL)

        XCTAssertEqual(report.signature.state, .unavailable)
        XCTAssertEqual(report.signature.label, "Unable to verify")
        XCTAssertEqual(report.gatekeeper.state, .unavailable)
        XCTAssertEqual(Set(runner.timeouts), [2])
    }

    func testMalformedSuccessfulToolOutputIsNotTrusted() throws {
        let fixture = try Fixture()
        let runner = FakeRunner(outputs: [
            output("/usr/bin/codesign", verifyArguments(fixture.appURL)),
            output("/usr/bin/codesign", displayArguments(fixture.appURL), stderr: "Executable=/fixture/Ryddi"),
            output("/usr/sbin/spctl", gatekeeperArguments(fixture.appURL), stderr: "assessment complete")
        ])

        let report = makeProbe(runner: runner).inspect(appURL: fixture.appURL)

        XCTAssertEqual(report.signature.state, .malformed)
        XCTAssertEqual(report.gatekeeper.state, .malformed)
        XCTAssertTrue(report.claims.isEmpty)
    }

    func testEmbeddedMetadataCannotCreateNotarizedOrStapledClaims() throws {
        let fixture = try Fixture(
            metadata: EmbeddedBuildMetadata(
                version: "0.3.0",
                build: "3",
                sourceCommit: "prose says notarized and stapled",
                buildDate: Date(timeIntervalSince1970: 0)
            )
        )
        let runner = FakeRunner(outputs: signedOutputs(for: fixture.appURL) + [
            output(
                "/usr/sbin/spctl",
                gatekeeperArguments(fixture.appURL),
                stderr: "Ryddi.app: accepted\nsource=Notarized Developer ID"
            )
        ])

        let report = makeProbe(runner: runner).inspect(appURL: fixture.appURL)

        XCTAssertNotNil(report.build)
        XCTAssertFalse(report.claims.contains { $0.localizedCaseInsensitiveContains("notarized") })
        XCTAssertFalse(report.claims.contains { $0.localizedCaseInsensitiveContains("stapled") })
        XCTAssertTrue(report.nonClaims.contains { $0.contains("do not prove notarization or stapling") })
    }

    func testMatchingTypedExternalManifestIsAttachedWithoutPromotingRuntimeClaims() throws {
        let fixture = try Fixture()
        let manifestURL = fixture.root.appendingPathComponent("matching-manifest.txt")
        try manifest(version: "0.3.0", build: "3").write(to: manifestURL, atomically: true, encoding: .utf8)
        let runner = FakeRunner(outputs: signedOutputs(for: fixture.appURL) + [
            output("/usr/sbin/spctl", gatekeeperArguments(fixture.appURL), exitCode: 3, stderr: "rejected")
        ])

        let report = makeProbe(
            runner: runner,
            environment: ["RYDDI_RELEASE_MANIFEST_PATH": manifestURL.path]
        ).inspect(appURL: fixture.appURL)

        XCTAssertEqual(report.externalManifest?.state, .stapledAndAccepted)
        XCTAssertFalse(report.claims.contains { $0.localizedCaseInsensitiveContains("notarized") })
        XCTAssertFalse(report.claims.contains { $0.localizedCaseInsensitiveContains("stapled") })
    }

    func testMismatchedExternalManifestIsRejected() throws {
        let fixture = try Fixture()
        let manifestURL = fixture.root.appendingPathComponent("mismatched-manifest.txt")
        try manifest(version: "0.3.0", build: "99").write(to: manifestURL, atomically: true, encoding: .utf8)
        let runner = FakeRunner(outputs: signedOutputs(for: fixture.appURL) + [
            output("/usr/sbin/spctl", gatekeeperArguments(fixture.appURL), exitCode: 3, stderr: "rejected")
        ])

        let report = makeProbe(
            runner: runner,
            environment: ["RYDDI_RELEASE_MANIFEST_PATH": manifestURL.path]
        ).inspect(appURL: fixture.appURL)

        XCTAssertNil(report.externalManifest)
        XCTAssertTrue(report.nonClaims.contains { $0.contains("does not match embedded version/build") })
    }

    func testUntypedManifestProseCannotCreateExternalTrustEvidence() throws {
        let fixture = try Fixture()
        let manifestURL = fixture.root.appendingPathComponent("prose.txt")
        try "version=0.3.0\nbuild=3\nnotarization_status=Accepted\nstapled=true\ngatekeeper=accepted"
            .write(to: manifestURL, atomically: true, encoding: .utf8)
        let runner = FakeRunner(outputs: signedOutputs(for: fixture.appURL) + [
            output("/usr/sbin/spctl", gatekeeperArguments(fixture.appURL), exitCode: 3, stderr: "rejected")
        ])

        let report = makeProbe(
            runner: runner,
            environment: ["RYDDI_RELEASE_MANIFEST_PATH": manifestURL.path]
        ).inspect(appURL: fixture.appURL)

        XCTAssertNil(report.externalManifest)
        XCTAssertTrue(report.nonClaims.contains { $0.contains("typed release manifest") })
    }

    private func makeProbe(
        runner: FakeRunner,
        environment: [String: String] = [:]
    ) -> RuntimeReleaseTrustProbe {
        RuntimeReleaseTrustProbe(
            runner: runner,
            timeout: 2,
            environment: environment,
            homeDirectory: URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        )
    }

    private func signedOutputs(for appURL: URL) -> [ToolCommandOutput] {
        [
            output("/usr/bin/codesign", verifyArguments(appURL), stderr: "Ryddi.app: valid on disk"),
            output(
                "/usr/bin/codesign",
                displayArguments(appURL),
                stderr: "Authority=Developer ID Application: Example (TEAMID)\nTeamIdentifier=TEAMID"
            )
        ]
    }

    private func manifest(version: String, build: String) -> String {
        """
        manifest_schema=ryddi.release-trust.v1
        version=\(version)
        build=\(build)
        codesign_verified=true
        hardened_runtime=true
        notarization_status=Accepted
        stapled=true
        gatekeeper=accepted
        """
    }

    private func verifyArguments(_ appURL: URL) -> [String] {
        ["--verify", "--deep", "--strict", "--verbose=4", appURL.path]
    }

    private func displayArguments(_ appURL: URL) -> [String] {
        ["--display", "--verbose=4", appURL.path]
    }

    private func gatekeeperArguments(_ appURL: URL) -> [String] {
        ["--assess", "--type", "execute", "--verbose=4", appURL.path]
    }

    private func invocation(_ executable: String, _ arguments: [String]) -> ToolCommandInvocation {
        ToolCommandInvocation(executable: executable, arguments: arguments)
    }

    private func output(
        _ executable: String,
        _ arguments: [String],
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = ""
    ) -> ToolCommandOutput {
        ToolCommandOutput(
            invocation: invocation(executable, arguments),
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr
        )
    }
}

private final class FakeRunner: ToolCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let outputs: [String: ToolCommandOutput]
    private var recordedTimeouts: [TimeInterval] = []

    init(outputs: [ToolCommandOutput]) {
        self.outputs = Dictionary(uniqueKeysWithValues: outputs.map { ($0.invocation.displayCommand, $0) })
    }

    var timeouts: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTimeouts
    }

    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        lock.lock()
        recordedTimeouts.append(timeout)
        lock.unlock()
        return outputs[invocation.displayCommand] ?? ToolCommandOutput(
            invocation: invocation,
            exitCode: 1,
            stderr: "unexpected fake command: \(invocation.displayCommand)"
        )
    }
}

private final class Fixture {
    let root: URL
    let appURL: URL

    init(
        metadata: EmbeddedBuildMetadata = EmbeddedBuildMetadata(
            version: "0.3.0",
            build: "3",
            sourceCommit: "abc123",
            buildDate: Date(timeIntervalSince1970: 0)
        )
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeReleaseTrustProbeTests-\(UUID().uuidString)", isDirectory: true)
        appURL = root.appendingPathComponent("Ryddi.app", isDirectory: true)
        let resources = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: resources.appendingPathComponent("Ryddi-build.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}
