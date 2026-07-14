import Foundation
import XCTest
@testable import ReclaimerCore

final class KnownHostsInspectorTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiKnownHosts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot, FileManager.default.fileExists(atPath: fixtureRoot.path) {
            try FileManager.default.removeItem(at: fixtureRoot)
        }
    }

    func testHashedKnownHostIsRecognizedThroughSSHKeygen() {
        let runner = RecordingKnownHostsRunner(output: output(
            arguments: ["-F", "vps.example", "-f", "/fixture/known_hosts"],
            stdout: """
            # Host vps.example found: line 4
            |1|fixture-salt|fixture-hash ssh-ed25519 ZmFrZS1zc2gta2V5LWJ5dGVz
            """
        ))

        let result = KnownHostsInspector(runner: runner).inspect(
            host: "vps.example",
            port: 22,
            file: URL(fileURLWithPath: "/fixture/known_hosts")
        )

        XCTAssertEqual(result.state, .known)
        XCTAssertEqual(result.keyType, "ssh-ed25519")
        XCTAssertEqual(result.fingerprint, "SHA256:m9ypiv/Ls2bNjCbLCsprd55hwx5B4xGeoCZMKXqbRdo")
        XCTAssertEqual(runner.invocations.first?.executable, "/usr/bin/ssh-keygen")
        XCTAssertEqual(
            runner.invocations.first?.arguments,
            ["-F", "vps.example", "-f", "/fixture/known_hosts"]
        )
        XCTAssertEqual(runner.timeouts, [5])
    }

    func testNonDefaultPortUsesBracketedHostQuery() {
        let query = "[2001:db8::10]:2222"
        let runner = RecordingKnownHostsRunner(output: output(
            arguments: ["-F", query, "-f", "/fixture/known_hosts"],
            stdout: "\(query) ssh-ed25519 ZmFrZS1zc2gta2V5LWJ5dGVz\n"
        ))

        let result = KnownHostsInspector(runner: runner).inspect(
            host: "2001:db8::10",
            port: 2222,
            file: URL(fileURLWithPath: "/fixture/known_hosts")
        )

        XCTAssertEqual(result.state, .known)
        XCTAssertEqual(
            runner.invocations.first?.arguments,
            ["-F", query, "-f", "/fixture/known_hosts"]
        )
    }

    func testNoMatchingHostIsUnknown() {
        let runner = RecordingKnownHostsRunner(output: output(
            arguments: ["-F", "missing.example", "-f", "/fixture/known_hosts"],
            exitCode: 1
        ))

        let result = KnownHostsInspector(runner: runner).inspect(
            host: "missing.example",
            port: nil,
            file: URL(fileURLWithPath: "/fixture/known_hosts")
        )

        XCTAssertEqual(result, KnownHostEvidence(state: .unknown, keyType: nil, fingerprint: nil))
    }

    func testInspectionFailureIsUnavailable() {
        let invocation = ToolCommandInvocation(
            executable: "/usr/bin/ssh-keygen",
            arguments: ["-F", "vps.example", "-f", "/fixture/known_hosts"]
        )
        let runner = RecordingKnownHostsRunner(output: ToolCommandOutput(
            invocation: invocation,
            exitCode: nil,
            launchError: "fixture launch failure"
        ))

        let result = KnownHostsInspector(runner: runner).inspect(
            host: "vps.example",
            port: 22,
            file: URL(fileURLWithPath: "/fixture/known_hosts")
        )

        XCTAssertEqual(result.state, .unavailable)
        XCTAssertNil(result.keyType)
        XCTAssertNil(result.fingerprint)
    }

    func testMalformedMatchingOutputDoesNotInventFingerprint() {
        let runner = RecordingKnownHostsRunner(output: output(
            arguments: ["-F", "vps.example", "-f", "/fixture/known_hosts"],
            stdout: "vps.example ssh-ed25519 definitely-not-base64***\n"
        ))

        let result = KnownHostsInspector(runner: runner).inspect(
            host: "vps.example",
            port: 22,
            file: URL(fileURLWithPath: "/fixture/known_hosts")
        )

        XCTAssertEqual(result.state, .unknown)
        XCTAssertNil(result.keyType)
        XCTAssertNil(result.fingerprint)
    }

    func testOutputBeyondBoundIsNotParsed() {
        let prefix = String(repeating: "# ignored fixture line\n", count: 30_000)
        let runner = RecordingKnownHostsRunner(output: output(
            arguments: ["-F", "vps.example", "-f", "/fixture/known_hosts"],
            stdout: prefix + "vps.example ssh-ed25519 ZmFrZS1zc2gta2V5LWJ5dGVz\n"
        ))

        let result = KnownHostsInspector(runner: runner).inspect(
            host: "vps.example",
            port: 22,
            file: URL(fileURLWithPath: "/fixture/known_hosts")
        )

        XCTAssertEqual(result.state, .unknown)
    }

    func testResolverListsNonWildcardAliasesAndUsesResolvedHostEvidence() throws {
        let sshRoot = fixtureRoot.appendingPathComponent("ssh", isDirectory: true)
        let includeRoot = sshRoot.appendingPathComponent("conf.d", isDirectory: true)
        try FileManager.default.createDirectory(at: includeRoot, withIntermediateDirectories: true)
        let configURL = sshRoot.appendingPathComponent("config")
        let includeURL = includeRoot.appendingPathComponent("extra.conf")
        let trailingWildcardURL = includeRoot.appendingPathComponent("team-alpha")
        let nonMatchingURL = includeRoot.appendingPathComponent("team")
        try """
        Include \(includeURL.path)
        Include \(includeRoot.path)/team-*

        Host prod-vps
          HostName 203.0.113.10
          User deploy
          Port 2222

        Host *.example.com
          User ignored
        """.write(to: configURL, atomically: true, encoding: .utf8)
        try """
        Host staging-vps
          HostName staging.example.invalid
          User ubuntu
        """.write(to: includeURL, atomically: true, encoding: .utf8)
        try """
        Host alpha-vps
          HostName alpha.example.invalid
        """.write(to: trailingWildcardURL, atomically: true, encoding: .utf8)
        try """
        Host should-not-load
          HostName broad-match-bug.example.invalid
        """.write(to: nonMatchingURL, atomically: true, encoding: .utf8)
        let knownHostsURL = sshRoot.appendingPathComponent("known_hosts")
        let sshOutput = output(
            "/usr/bin/ssh",
            arguments: ["-G", "prod-vps"],
            stdout: """
            user deploy
            hostname 203.0.113.10
            port 2222
            identityfile ~/.ssh/id_ed25519
            """
        )
        let keygenOutput = output(
            arguments: ["-F", "[203.0.113.10]:2222", "-f", knownHostsURL.path],
            stdout: "[203.0.113.10]:2222 ssh-ed25519 ZmFrZS1zc2gta2V5LWJ5dGVz\n"
        )
        let runner = MappedKnownHostsRunner(outputs: [sshOutput, keygenOutput])
        let resolver = RemoteTargetResolver(
            configURL: configURL,
            knownHostsURL: knownHostsURL,
            runner: runner
        )

        let targets = resolver.targets()
        XCTAssertEqual(targets.map(\.input), ["alpha-vps", "prod-vps", "staging-vps"])
        XCTAssertFalse(targets.contains { $0.input.contains("*") })
        XCTAssertFalse(targets.contains { $0.input == "should-not-load" })

        let resolved = try resolver.resolve("prod-vps")
        XCTAssertEqual(resolved.alias, "prod-vps")
        XCTAssertEqual(resolved.resolvedUser, "deploy")
        XCTAssertEqual(resolved.resolvedHost, "203.0.113.10")
        XCTAssertEqual(resolved.resolvedPort, 2222)
        XCTAssertEqual(resolved.knownHostsState, "known")
        XCTAssertEqual(resolved.fingerprint, "SHA256:m9ypiv/Ls2bNjCbLCsprd55hwx5B4xGeoCZMKXqbRdo")
        XCTAssertEqual(runner.commands, [
            "/usr/bin/ssh -G prod-vps",
            "/usr/bin/ssh-keygen -F [203.0.113.10]:2222 -f \(knownHostsURL.path)"
        ])
    }

    private func output(
        _ executable: String = "/usr/bin/ssh-keygen",
        arguments: [String],
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = ""
    ) -> ToolCommandOutput {
        ToolCommandOutput(
            invocation: ToolCommandInvocation(
                executable: executable,
                arguments: arguments
            ),
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr
        )
    }
}

private final class MappedKnownHostsRunner: ToolCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let outputs: [String: ToolCommandOutput]
    private var recordedCommands = [String]()

    init(outputs: [ToolCommandOutput]) {
        self.outputs = Dictionary(uniqueKeysWithValues: outputs.map {
            ($0.invocation.displayCommand, $0)
        })
    }

    var commands: [String] {
        lock.withLock { recordedCommands }
    }

    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        lock.withLock { recordedCommands.append(invocation.displayCommand) }
        return outputs[invocation.displayCommand] ?? ToolCommandOutput(
            invocation: invocation,
            exitCode: 1,
            stderr: "unexpected fixture command"
        )
    }
}

private final class RecordingKnownHostsRunner: ToolCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let output: ToolCommandOutput
    private var recordedInvocations = [ToolCommandInvocation]()
    private var recordedTimeouts = [TimeInterval]()

    init(output: ToolCommandOutput) {
        self.output = output
    }

    var invocations: [ToolCommandInvocation] {
        lock.withLock { recordedInvocations }
    }

    var timeouts: [TimeInterval] {
        lock.withLock { recordedTimeouts }
    }

    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        lock.withLock {
            recordedInvocations.append(invocation)
            recordedTimeouts.append(timeout)
        }
        return ToolCommandOutput(
            invocation: invocation,
            exitCode: output.exitCode,
            timedOut: output.timedOut,
            stdout: output.stdout,
            stderr: output.stderr,
            launchError: output.launchError
        )
    }
}
