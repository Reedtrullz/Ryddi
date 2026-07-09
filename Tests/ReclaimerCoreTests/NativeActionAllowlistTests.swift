import XCTest
@testable import ReclaimerCore

final class NativeActionAllowlistTests: XCTestCase {
    func testHomebrewCleanupAllowsOnlyExactArgv() {
        let allowed = NativeActionCommand(
            kind: .homebrewCleanup,
            executable: "/opt/homebrew/bin/brew",
            arguments: ["cleanup", "--dry-run"]
        )
        XCTAssertEqual(NativeActionAllowlist.validate(allowed), .allowed)

        let shellWrapped = NativeActionCommand(
            kind: .homebrewCleanup,
            executable: "/bin/sh",
            arguments: ["-c", "brew cleanup"]
        )
        XCTAssertEqual(NativeActionAllowlist.validate(shellWrapped), .blocked("shell execution is not allowed"))

        let destructiveOtherTool = NativeActionCommand(
            kind: .homebrewCleanup,
            executable: "/usr/bin/rm",
            arguments: ["-rf", "/tmp/example"]
        )
        XCTAssertEqual(NativeActionAllowlist.validate(destructiveOtherTool), .blocked("unexpected executable for homebrewCleanup"))
    }

    func testAllowlistBlocksShellMetacharactersInExecutableAndArguments() {
        let dangerousValues = [
            "brew && rm -rf /",
            "brew; rm -rf /",
            "brew\ncleanup",
            "`brew`",
            "$(brew)"
        ]

        for value in dangerousValues {
            let executableCommand = NativeActionCommand(kind: .homebrewCleanup, executable: value, arguments: ["cleanup"])
            XCTAssertEqual(NativeActionAllowlist.validate(executableCommand), .blocked("shell metacharacters are not allowed"))

            let argumentCommand = NativeActionCommand(kind: .homebrewCleanup, executable: "brew", arguments: ["cleanup", value])
            XCTAssertEqual(NativeActionAllowlist.validate(argumentCommand), .blocked("shell metacharacters are not allowed"))
        }
    }

    func testNativeExecutorRecordsBlockedAllowlistReceiptWithoutLaunchingCommand() {
        let command = NativeToolCommand(
            id: "brew.cleanup",
            command: "/bin/sh -c brew cleanup",
            purpose: "Try to wrap Homebrew cleanup in a shell.",
            risk: .reclaim,
            requiresReview: true,
            expectedEffect: "Should be blocked before launch."
        )
        let receipt = NativeToolReceipt(
            findingPath: "/Users/reidar/Library/Caches/Homebrew",
            displayName: "Homebrew",
            category: "Developer cache",
            allocatedSize: 123,
            safetyClass: .safeAfterCondition,
            actionKind: .nativeToolCommand,
            status: "native-tool",
            message: "Homebrew cleanup",
            commands: [command],
            nonClaims: []
        )
        let runner = RecordingNativeActionRunner()
        let executor = NativeToolExecutor(runner: runner)

        let executionReceipt = executor.execute(
            selection: NativeToolCommandSelection(receipt: receipt, command: command),
            mode: .perform,
            ruleVersion: "test",
            userConfirmed: true
        )

        XCTAssertEqual(executionReceipt.status, "blocked")
        XCTAssertEqual(executionReceipt.message, "shell execution is not allowed")
        XCTAssertTrue(executionReceipt.errors.contains("shell execution is not allowed"))
        XCTAssertTrue(runner.invocations.isEmpty)
    }
}

private final class RecordingNativeActionRunner: ToolCommandRunning, @unchecked Sendable {
    private(set) var invocations: [ToolCommandInvocation] = []

    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        invocations.append(invocation)
        return ToolCommandOutput(invocation: invocation, exitCode: 0)
    }
}
