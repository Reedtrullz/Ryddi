import XCTest
@testable import ReclaimerCore

final class RemoteTargetInputPolicyTests: XCTestCase {
    func testRemoteTargetInputPolicyAcceptsCommonTargetsAndRejectsSSHOptions() throws {
        for target in ["prod-vps", "deploy@prod-vps", "203.0.113.10", "2001:db8::10", "Racknerd-Deploy"] {
            XCTAssertNoThrow(try RemoteTargetInputPolicy.validate(target), target)
        }

        for target in ["", "   ", "-oForwardAgent=yes", "-F/tmp/ssh_config", "prod vps", "prod\nvps", String(repeating: "a", count: 256)] {
            XCTAssertThrowsError(try RemoteTargetInputPolicy.validate(target), target)
        }
    }

    func testRemoteTargetResolverRejectsInvalidTargetBeforeSSHConfigDump() throws {
        let runner = RecordingToolRunner()
        let resolver = RemoteTargetResolver(
            configURL: URL(fileURLWithPath: "/tmp/missing-ryddi-ssh-config"),
            knownHostsURL: URL(fileURLWithPath: "/tmp/missing-ryddi-known-hosts"),
            runner: runner
        )

        XCTAssertThrowsError(try resolver.resolve("-oForwardAgent=yes")) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("invalid remote target"))
        }
        XCTAssertTrue(runner.commands.isEmpty)
    }

    func testRemoteSSHRunnerRejectsInvalidTargetBeforeLaunch() throws {
        let runner = RecordingToolRunner()
        let ssh = RemoteSSHCommandRunner(target: RemoteTargetReference(input: "-oForwardAgent=yes"), runner: runner)

        let result = ssh.run(commandID: "probe.uname", remoteCommand: "uname -srm")

        XCTAssertNil(result.exitCode)
        XCTAssertTrue(result.stderrPreview.contains { $0.localizedCaseInsensitiveContains("invalid remote target") })
        XCTAssertTrue(runner.commands.isEmpty)
    }
}

private final class RecordingToolRunner: ToolCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var commands: [String] = []

    func run(_ invocation: ToolCommandInvocation, timeout _: TimeInterval) -> ToolCommandOutput {
        lock.lock()
        commands.append(invocation.displayCommand)
        lock.unlock()
        return ToolCommandOutput(invocation: invocation, exitCode: 0)
    }
}
