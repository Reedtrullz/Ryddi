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

    func testFailedHomebrewCommandStillWritesBoundedReceiptWithoutAfterSnapshot() {
        let runner = RecordingNativeActionReceiptRunner(
            exitCode: 2,
            stdout: "line 1\nline 2\n",
            stderr: "warning 1\nwarning 2\n"
        )
        let receipt = NativeActionExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 1, diskStatusPath: tempRoot, previewLineLimit: 1)
        ).executeHomebrewCleanup(mode: .dryRun, userConfirmed: false)

        XCTAssertEqual(receipt.mode, .dryRun)
        XCTAssertEqual(receipt.exitCode, 2)
        XCTAssertEqual(receipt.stdoutPreview, ["line 1"])
        XCTAssertEqual(receipt.stderrPreview, ["warning 1"])
        XCTAssertNotNil(receipt.beforeDisk)
        XCTAssertNil(receipt.afterDisk)
        XCTAssertTrue(receipt.nonClaims.contains { $0.localizedCaseInsensitiveContains("APFS free space") })
    }

    func testNativeToolExecutionReceiptReportRedactsAndEscapesMarkdown() throws {
        let receipt = NativeToolExecutionReceipt(
            id: "native-receipt-pipe",
            createdAt: Date(timeIntervalSince1970: 10),
            ruleVersion: "rules-v1",
            mode: .dryRun,
            status: "dry-run",
            findingPath: "/Users/reidar/Library/Caches/Homebrew",
            category: "Developer | cache",
            command: NativeToolCommand(
                id: "brew.preview",
                command: "brew cleanup -n",
                purpose: "Preview | Homebrew\ncleanup.",
                risk: .inspect,
                requiresReview: false,
                expectedEffect: "Shows what Homebrew would remove.",
                workingDirectory: "/Users/reidar/Library/Caches/Homebrew",
                context: "local | native"
            ),
            invocation: ToolCommandInvocation(executable: "brew", arguments: ["cleanup", "-n"]),
            beforeFreeBytes: 1_000,
            afterFreeBytes: 1_000,
            output: ToolCommandSnapshot(output: ToolCommandOutput(
                invocation: ToolCommandInvocation(executable: "brew", arguments: ["cleanup", "-n"]),
                exitCode: 0,
                stdout: "Would remove /Users/reidar/Library/Caches/Homebrew/bottle|one\n",
                stderr: ""
            )),
            userConfirmed: false,
            message: "Dry run only for /Users/reidar/Library/Caches/Homebrew",
            errors: [],
            nonClaims: NativeToolExecutor.nonClaims
        )

        let report = NativeToolExecutionReceiptReportBuilder.build(
            receipt: receipt,
            privacy: ReportPrivacyOptions(
                pathStyle: .redacted,
                homeDirectory: URL(fileURLWithPath: "/Users/reidar")
            ),
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(report.receiptID, receipt.id)
        XCTAssertEqual(report.commandID, "brew.preview")
        XCTAssertEqual(report.status, "dry-run")
        XCTAssertFalse(report.markdown.contains("/Users/reidar/Library/Caches/Homebrew"))
        XCTAssertTrue(report.markdown.contains("<path redacted>"))
        XCTAssertTrue(report.markdown.contains("Developer \\| cache"))
        XCTAssertTrue(report.markdown.contains("Preview \\| Homebrew cleanup."))
        XCTAssertTrue(report.markdown.contains("does not execute cleanup"))
        XCTAssertTrue(report.markdown.contains("do not authorize generic file deletion"))
    }
}

private final class RecordingNativeActionReceiptRunner: ToolCommandRunning, @unchecked Sendable {
    private(set) var invocations: [ToolCommandInvocation] = []
    private let exitCode: Int32
    private let stdout: String
    private let stderr: String

    init(exitCode: Int32 = 0, stdout: String, stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        invocations.append(invocation)
        return ToolCommandOutput(invocation: invocation, exitCode: exitCode, stdout: stdout, stderr: stderr)
    }
}
