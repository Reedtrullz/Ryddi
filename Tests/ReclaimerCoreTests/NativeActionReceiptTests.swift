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
        XCTAssertNil(receipt.afterDisk)
        XCTAssertNil(receipt.skippedReason)
        XCTAssertTrue(receipt.nonClaims.contains("Homebrew decides the exact cleanup set."))
    }

    func testHomebrewCleanupSelectionRequiresFreshSameProcessPreview() {
        let selection = NativeActionReceiptBridge.homebrewCleanupSelection(
            findingPath: tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        )

        XCTAssertEqual(selection.receipt.status, "preview-required")
        XCTAssertTrue(selection.receipt.message.localizedCaseInsensitiveContains("fresh preview"))
        XCTAssertTrue(selection.receipt.message.localizedCaseInsensitiveContains("same process"))
        XCTAssertFalse(selection.receipt.message.localizedCaseInsensitiveContains("saved"))
    }

    func testPublicReceiptAuthorizationCannotRunHomebrewCleanup() {
        let findingPath = tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        let authorization = NativeToolPerformAuthorization(
            previewReceipt: actualPreviewReceipt(
                findingPath: findingPath,
                createdAt: Date(),
                arguments: ["cleanup", "--dry-run"]
            )
        )
        let runner = RecordingNativeActionReceiptRunner(stdout: "Removing old download\n")
        let receipt = NativeActionExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 1, diskStatusPath: tempRoot)
        ).executeHomebrewCleanup(
            mode: .perform,
            userConfirmed: true,
            authorization: authorization,
            ruleVersion: "rules-v1",
            findingPath: findingPath
        )

        XCTAssertTrue(runner.invocations.isEmpty)
        XCTAssertEqual(receipt.commandDisplay, ["brew", "cleanup"])
        XCTAssertEqual(receipt.mode, .perform)
        XCTAssertTrue(receipt.skippedReason?.localizedCaseInsensitiveContains("same-process") ?? false)
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

    func testHomebrewPerformRequiresSameProcessCapabilityEvenWhenConfirmed() {
        let runner = RecordingNativeActionReceiptRunner(stdout: "should not run\n")
        let receipt = NativeActionExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 1, diskStatusPath: tempRoot)
        ).executeHomebrewCleanup(mode: .perform, userConfirmed: true)

        XCTAssertTrue(runner.invocations.isEmpty)
        XCTAssertTrue(receipt.skippedReason?.localizedCaseInsensitiveContains("same-process") ?? false)
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
        XCTAssertFalse(report.markdown.contains("| After free |"))
        XCTAssertFalse(report.markdown.contains("| Free-space delta |"))
    }

    func testHomebrewNativeActionReceiptBridgesToCanonicalNativeToolReceipt() throws {
        let runner = RecordingNativeActionReceiptRunner(stdout: "Would remove bottle\n")
        let actionReceipt = NativeActionExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 1, diskStatusPath: tempRoot)
        ).executeHomebrewCleanup(mode: .dryRun, userConfirmed: false)

        let receipt = NativeActionReceiptBridge.nativeToolExecutionReceipt(
            from: actionReceipt,
            ruleVersion: "rules-v1",
            findingPath: "/Users/reidar/Library/Caches/Homebrew",
            userConfirmed: false
        )

        XCTAssertEqual(receipt.id, actionReceipt.id)
        XCTAssertEqual(receipt.mode, .dryRun)
        XCTAssertEqual(receipt.status, "dry-run")
        XCTAssertEqual(receipt.command.id, "brew.preview")
        XCTAssertEqual(receipt.invocation?.executable, "brew")
        XCTAssertEqual(receipt.invocation?.arguments, ["cleanup", "--dry-run"])
        XCTAssertEqual(receipt.output?.stdoutPreview, ["Would remove bottle"])
        XCTAssertNil(receipt.afterFreeBytes)
        XCTAssertFalse(receipt.userConfirmed)
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("dry run completed"))
        XCTAssertTrue(receipt.nonClaims.contains { $0.localizedCaseInsensitiveContains("Native command receipts") })
    }

    func testPersistedHomebrewPreviewReceiptRemainsEvidenceOnly() throws {
        let findingPath = "/Users/reidar/Library/Caches/Homebrew"
        let selection = NativeActionReceiptBridge.homebrewCleanupSelection(findingPath: findingPath)
        let noOutputPreview = NativeToolExecutionReceipt(
            ruleVersion: "rules-v1",
            mode: .dryRun,
            status: "dry-run",
            findingPath: findingPath,
            category: "Homebrew",
            command: NativeToolCommand(
                id: "brew.preview",
                command: "brew cleanup -n",
                purpose: "Preview Homebrew cleanup.",
                risk: .inspect,
                requiresReview: false,
                expectedEffect: "Shows what Homebrew would remove."
            ),
            invocation: ToolCommandInvocation(executable: "brew", arguments: ["cleanup", "-n"]),
            beforeFreeBytes: 100,
            afterFreeBytes: 100,
            output: nil,
            userConfirmed: false,
            message: "Dry run only; would execute Homebrew preview.",
            nonClaims: NativeToolExecutor.nonClaims
        )

        XCTAssertFalse(NativeToolExecutor.savedDryRunReceipt(noOutputPreview, authorizes: selection, ruleVersion: "rules-v1"))

        let actualPreview = NativeActionReceiptBridge.nativeToolExecutionReceipt(
            from: NativeActionExecutor(
                runner: RecordingNativeActionReceiptRunner(stdout: "Would remove bottle\n"),
                configuration: NativeActionExecutionConfiguration(timeout: 1, diskStatusPath: tempRoot)
            ).executeHomebrewCleanup(mode: .dryRun, userConfirmed: false),
            ruleVersion: "rules-v1",
            findingPath: findingPath,
            userConfirmed: false
        )

        XCTAssertFalse(NativeToolExecutor.savedDryRunReceipt(actualPreview, authorizes: selection, ruleVersion: "rules-v1"))
    }

    func testSyntheticCleanupDryRunReceiptCannotAuthorizePerform() {
        let findingPath = tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        let selection = NativeActionReceiptBridge.homebrewCleanupSelection(findingPath: findingPath)
        let syntheticCleanup = NativeToolExecutionReceipt(
            ruleVersion: "rules-v1",
            mode: .dryRun,
            status: "dry-run",
            findingPath: findingPath,
            category: "Homebrew",
            command: selection.command,
            invocation: ToolCommandInvocation(executable: "brew", arguments: ["cleanup"]),
            beforeFreeBytes: 100,
            afterFreeBytes: 100,
            output: nil,
            userConfirmed: false,
            message: "Synthetic same-command dry run.",
            nonClaims: NativeToolExecutor.nonClaims
        )

        XCTAssertFalse(NativeToolExecutor.savedDryRunReceipt(syntheticCleanup, authorizes: selection, ruleVersion: "rules-v1"))
    }

    func testBrewPreviewDryRunExecutesRunnerAndCapturesOutput() throws {
        let findingPath = tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        let preview = NativeToolCommand(
            id: "brew.preview",
            command: "brew cleanup --dry-run",
            purpose: "Preview Homebrew cleanup.",
            risk: .inspect,
            requiresReview: false,
            expectedEffect: "Shows what Homebrew would remove."
        )
        let selection = NativeToolCommandSelection(
            receipt: NativeToolReceipt(
                findingPath: findingPath,
                displayName: "Homebrew cache",
                category: "Homebrew",
                allocatedSize: 100,
                safetyClass: .safeAfterCondition,
                actionKind: .nativeToolCommand,
                status: "native-tool",
                message: "Preview Homebrew cleanup.",
                commands: [preview],
                nonClaims: []
            ),
            command: preview
        )
        let runner = RecordingNativeActionReceiptRunner(stdout: "Would remove bottle\n")

        let receipt = NativeToolExecutor(
            runner: runner,
            configuration: NativeToolExecutionConfiguration(timeout: 3, diskStatusPath: tempRoot)
        ).execute(
            selection: selection,
            mode: .dryRun,
            ruleVersion: "rules-v1",
            userConfirmed: false
        )

        XCTAssertEqual(runner.invocations.map(\.arguments), [["cleanup", "--dry-run"]])
        XCTAssertEqual(receipt.status, "dry-run")
        XCTAssertEqual(receipt.output?.stdoutPreview, ["Would remove bottle"])
        XCTAssertTrue(receipt.errors.isEmpty)
    }

    func testStaleOrLooseArgvHomebrewPreviewCannotAuthorizePerform() {
        let findingPath = tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        let selection = NativeActionReceiptBridge.homebrewCleanupSelection(findingPath: findingPath)
        let stalePreview = actualPreviewReceipt(
            findingPath: findingPath,
            createdAt: Date().addingTimeInterval(-3_600),
            arguments: ["cleanup", "--dry-run"]
        )
        let looseArgvPreview = actualPreviewReceipt(
            findingPath: findingPath,
            createdAt: Date(),
            arguments: ["cleanup", "--dry-run", "--prune=all"]
        )

        XCTAssertFalse(NativeToolExecutor.savedDryRunReceipt(stalePreview, authorizes: selection, ruleVersion: "rules-v1"))
        XCTAssertFalse(NativeToolExecutor.savedDryRunReceipt(looseArgvPreview, authorizes: selection, ruleVersion: "rules-v1"))
    }

    func testNativeToolPerformWithoutPreviewAuthorizationIsBlockedInsideExecutor() {
        let findingPath = tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        let selection = NativeActionReceiptBridge.homebrewCleanupSelection(findingPath: findingPath)
        let runner = RecordingNativeActionReceiptRunner(stdout: "must not run\n")

        let receipt = NativeToolExecutor(
            runner: runner,
            configuration: NativeToolExecutionConfiguration(timeout: 3, diskStatusPath: tempRoot)
        ).execute(
            selection: selection,
            mode: .perform,
            ruleVersion: "rules-v1",
            userConfirmed: true
        )

        XCTAssertEqual(receipt.status, "blocked")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("same-process"))
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testExecutorMintedPreviewAuthorizesOnlyMatchingFreshCleanupOnce() {
        let findingPath = tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        let otherPath = tempRoot.appendingPathComponent("Library/Caches/Other").path
        let now = Date(timeIntervalSince1970: 100)
        let runner = RecordingNativeActionReceiptRunner(stdout: "Removed old bottle\n")
        let executor = NativeActionExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 3, diskStatusPath: tempRoot),
            now: { now }
        )
        let preview = executor.previewHomebrewCleanup(ruleVersion: "rules-v1", findingPath: findingPath)

        let wrongPath = executor.performHomebrewCleanup(
            using: preview,
            userConfirmed: true,
            ruleVersion: "rules-v1",
            findingPath: otherPath
        )
        XCTAssertTrue(wrongPath.skippedReason?.localizedCaseInsensitiveContains("does not match") ?? false)
        XCTAssertEqual(runner.invocations.map(\.arguments), [["cleanup", "--dry-run"]])

        let receipt = executor.performHomebrewCleanup(
            using: preview,
            userConfirmed: true,
            ruleVersion: "rules-v1",
            findingPath: findingPath
        )
        XCTAssertEqual(receipt.exitCode, 0)
        XCTAssertEqual(runner.invocations.map(\.arguments), [["cleanup", "--dry-run"], ["cleanup"]])
        XCTAssertEqual(receipt.stdoutPreview, ["Removed old bottle"])

        let reused = executor.performHomebrewCleanup(
            using: preview,
            userConfirmed: true,
            ruleVersion: "rules-v1",
            findingPath: findingPath
        )
        XCTAssertTrue(reused.skippedReason?.localizedCaseInsensitiveContains("already been used") ?? false)
        XCTAssertEqual(runner.invocations.map(\.arguments), [["cleanup", "--dry-run"], ["cleanup"]])
    }

    func testJSONDecodedNativePreviewReceiptCannotAuthorizePerform() throws {
        let findingPath = tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        let selection = NativeActionReceiptBridge.homebrewCleanupSelection(findingPath: findingPath)
        let encoded = try JSONEncoder().encode(actualPreviewReceipt(
            findingPath: findingPath,
            createdAt: Date(),
            arguments: ["cleanup", "--dry-run"]
        ))
        let decoded = try JSONDecoder().decode(NativeToolExecutionReceipt.self, from: encoded)
        let runner = RecordingNativeActionReceiptRunner(stdout: "must not run\n")

        let receipt = NativeToolExecutor(
            runner: runner,
            configuration: NativeToolExecutionConfiguration(timeout: 3, diskStatusPath: tempRoot)
        ).execute(
            selection: selection,
            mode: .perform,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            authorization: NativeToolPerformAuthorization(previewReceipt: decoded)
        )

        XCTAssertEqual(receipt.status, "blocked")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("evidence only"))
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testPreviewAuthorizationRejectsFailedWrongPathWrongRuleAndDigest() {
        let findingPath = tempRoot.appendingPathComponent("Library/Caches/Homebrew").path
        let selection = NativeActionReceiptBridge.homebrewCleanupSelection(findingPath: findingPath)
        let valid = actualPreviewReceipt(
            findingPath: findingPath,
            createdAt: Date(),
            arguments: ["cleanup", "--dry-run"]
        )
        let failed = actualPreviewReceipt(
            findingPath: findingPath,
            createdAt: Date(),
            arguments: ["cleanup", "--dry-run"],
            exitCode: 1
        )
        let wrongDigest = actualPreviewReceipt(
            findingPath: findingPath,
            createdAt: Date(),
            arguments: ["cleanup", "--dry-run"],
            authorizationDigest: "wrong-digest"
        )
        let wrongPathSelection = NativeActionReceiptBridge.homebrewCleanupSelection(
            findingPath: tempRoot.appendingPathComponent("different/Homebrew").path
        )

        XCTAssertNil(NativeToolExecutor.performAuthorization(
            authorizing: selection,
            in: [failed],
            ruleVersion: "rules-v1"
        ))
        XCTAssertNil(NativeToolExecutor.performAuthorization(
            authorizing: wrongPathSelection,
            in: [valid],
            ruleVersion: "rules-v1"
        ))
        XCTAssertNil(NativeToolExecutor.performAuthorization(
            authorizing: selection,
            in: [valid],
            ruleVersion: "rules-v2"
        ))
        XCTAssertNil(NativeToolExecutor.performAuthorization(
            authorizing: selection,
            in: [wrongDigest],
            ruleVersion: "rules-v1"
        ))
    }

    private func actualPreviewReceipt(
        findingPath: String,
        createdAt: Date,
        arguments: [String],
        ruleVersion: String = "rules-v1",
        exitCode: Int32 = 0,
        authorizationDigest: String? = nil
    ) -> NativeToolExecutionReceipt {
        let invocation = ToolCommandInvocation(executable: "brew", arguments: arguments)
        return NativeToolExecutionReceipt(
            createdAt: createdAt,
            ruleVersion: ruleVersion,
            mode: .dryRun,
            status: exitCode == 0 ? "dry-run" : "failed",
            findingPath: findingPath,
            category: "Homebrew",
            command: NativeToolCommand(
                id: "brew.preview",
                command: invocation.displayCommand,
                purpose: "Preview Homebrew cleanup.",
                risk: .inspect,
                requiresReview: false,
                expectedEffect: "Shows what Homebrew would remove."
            ),
            invocation: invocation,
            authorizationDigest: authorizationDigest
                ?? NativeToolExecutor.homebrewCleanupAuthorizationDigest(
                    findingPath: findingPath,
                    ruleVersion: ruleVersion
                ),
            beforeFreeBytes: 100,
            afterFreeBytes: 100,
            output: ToolCommandSnapshot(output: ToolCommandOutput(
                invocation: invocation,
                exitCode: exitCode,
                stdout: "Would remove bottle\n"
            )),
            userConfirmed: false,
            message: "Actual Homebrew preview.",
            errors: exitCode == 0 ? [] : ["Command failed."],
            nonClaims: NativeToolExecutor.nonClaims
        )
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
