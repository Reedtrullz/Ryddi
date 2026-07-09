import XCTest
@testable import ReclaimerCore

final class NativeActionReceiptTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiNativeActionReceiptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testHomebrewDryRunUsesCleanupDryRunArgvAndWritesReceipt() {
        let runner = RecordingNativeActionReceiptRunner(stdout: "Would remove bottle\n")
        let receipt = NativeActionExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 1, diskStatusPath: tempRoot)
        ).executeHomebrewCleanup(mode: .dryRun, userConfirmed: false)

        XCTAssertEqual(runner.invocations.first?.executable, "brew")
        XCTAssertEqual(runner.invocations.first?.arguments, ["cleanup", "--dry-run"])
        XCTAssertEqual(receipt.kind, .homebrewCleanup)
        XCTAssertEqual(receipt.mode, .dryRun)
        XCTAssertEqual(receipt.commandDisplay, ["brew", "cleanup", "--dry-run"])
        XCTAssertEqual(receipt.exitCode, 0)
        XCTAssertEqual(receipt.stdoutPreview, ["Would remove bottle"])
        XCTAssertNotNil(receipt.beforeDisk)
        XCTAssertNotNil(receipt.afterDisk)
        XCTAssertNil(receipt.skippedReason)
        XCTAssertTrue(receipt.nonClaims.contains("Homebrew decides the exact cleanup set."))
    }

    func testHomebrewPerformUsesCleanupArgvWithoutShellInterpolation() {
        let runner = RecordingNativeActionReceiptRunner(stdout: "Removing old download\n")
        let receipt = NativeActionExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 1, diskStatusPath: tempRoot)
        ).executeHomebrewCleanup(mode: .perform, userConfirmed: true)

        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(runner.invocations.first?.executable, "brew")
        XCTAssertEqual(runner.invocations.first?.arguments, ["cleanup"])
        XCTAssertFalse(runner.invocations.first?.displayCommand.contains("/bin/sh") ?? true)
        XCTAssertEqual(receipt.commandDisplay, ["brew", "cleanup"])
        XCTAssertEqual(receipt.mode, .perform)
        XCTAssertNil(receipt.skippedReason)
    }

    func testHomebrewPerformRequiresExplicitConfirmation() {
        let runner = RecordingNativeActionReceiptRunner(stdout: "should not run\n")
        let receipt = NativeActionExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 1, diskStatusPath: tempRoot)
        ).executeHomebrewCleanup(mode: .perform, userConfirmed: false)

        XCTAssertTrue(runner.invocations.isEmpty)
        XCTAssertEqual(receipt.skippedReason, "Homebrew cleanup requires explicit confirmation.")
        XCTAssertNil(receipt.afterDisk)
    }
}

private final class RecordingNativeActionReceiptRunner: ToolCommandRunning, @unchecked Sendable {
    private(set) var invocations: [ToolCommandInvocation] = []
    private let stdout: String

    init(stdout: String) {
        self.stdout = stdout
    }

    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        invocations.append(invocation)
        return ToolCommandOutput(invocation: invocation, exitCode: 0, stdout: stdout)
    }
}
