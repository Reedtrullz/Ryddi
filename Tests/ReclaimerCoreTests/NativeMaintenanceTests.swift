import XCTest
@testable import ReclaimerCore

final class NativeMaintenanceTests: XCTestCase {
    func testAllowlistOnlyAcceptsExactDockerAndNpmArgv() {
        XCTAssertEqual(
            NativeActionAllowlist.validate(NativeActionCommand(
                kind: .dockerBuilderPrune,
                executable: "docker",
                arguments: ["--context", "colima", "builder", "prune", "--force"]
            )),
            .allowed
        )
        XCTAssertEqual(
            NativeActionAllowlist.validate(NativeActionCommand(
                kind: .dockerBuilderPrune,
                executable: "docker",
                arguments: ["builder", "prune", "--force"]
            )),
            .blocked("dockerBuilderPrune requires an explicit safe context")
        )
        XCTAssertEqual(
            NativeActionAllowlist.validate(NativeActionCommand(
                kind: .dockerBuilderPrune,
                executable: "docker",
                arguments: ["--context", "../../remote", "builder", "prune", "--force"]
            )),
            .blocked("dockerBuilderPrune requires an explicit safe context")
        )
        XCTAssertEqual(
            NativeActionAllowlist.validate(NativeActionCommand(
                kind: .dockerBuilderPrune,
                executable: "docker",
                arguments: ["--context", "colima", "system", "prune"]
            )),
            .blocked("unexpected arguments for dockerBuilderPrune")
        )
        XCTAssertEqual(
            NativeActionAllowlist.validate(NativeActionCommand(
                kind: .dockerBuilderPrune,
                executable: "docker",
                arguments: ["--context", "colima", "volume", "prune"]
            )),
            .blocked("unexpected arguments for dockerBuilderPrune")
        )
        XCTAssertEqual(
            NativeActionAllowlist.validate(NativeActionCommand(
                kind: .npmCacheClean,
                executable: "npm",
                arguments: ["cache", "clean", "--force"]
            )),
            .allowed
        )
        XCTAssertEqual(
            NativeActionAllowlist.validate(NativeActionCommand(
                kind: .npmCacheClean,
                executable: "npm",
                arguments: ["cache", "clean", "--force", "--prefix", "/tmp"]
            )),
            .blocked("unexpected arguments for npmCacheClean")
        )
        XCTAssertEqual(
            NativeActionAllowlist.validate(NativeActionCommand(
                kind: .npmCacheClean,
                executable: "/bin/sh",
                arguments: ["-c", "npm cache clean --force"]
            )),
            .blocked("shell execution is not allowed")
        )
    }

    func testDockerPreviewThenPerformUsesSameProcessCapabilityAndExactCommands() {
        let runner = RecordingMaintenanceRunner()
        let executor = NativeMaintenanceExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 2),
            now: { Date(timeIntervalSince1970: 100) }
        )
        let preview = executor.preview(
            action: .dockerBuilderPrune,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test"
        )

        XCTAssertEqual(preview.receipt.mode, .dryRun)
        XCTAssertEqual(preview.receipt.exitCode, 0)
        XCTAssertEqual(preview.contextName, "colima")

        let performed = executor.perform(
            using: preview,
            userConfirmed: true,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test"
        )

        XCTAssertEqual(performed.mode, .perform)
        XCTAssertEqual(performed.exitCode, 0)
        XCTAssertEqual(performed.commandDisplay, ["docker", "--context", "colima", "builder", "prune", "--force"])
        XCTAssertEqual(runner.invocations.map(\.displayCommand), [
            "docker context show",
            "docker --context colima system df -v",
            "docker --context colima builder prune --force"
        ])

        let reused = executor.perform(
            using: preview,
            userConfirmed: true,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test"
        )
        XCTAssertNil(reused.exitCode)
        XCTAssertTrue(reused.skippedReason?.localizedCaseInsensitiveContains("already") ?? false)
    }

    func testDockerPreviewBindsInspectionAndPerformToObservedContextEvenWhenAmbientContextChanges() {
        let runner = ContextSwitchingMaintenanceRunner()
        let executor = NativeMaintenanceExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 2),
            now: { Date(timeIntervalSince1970: 100) }
        )
        let preview = executor.preview(
            action: .dockerBuilderPrune,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test"
        )

        runner.ambientContext = "remote-production"
        let performed = executor.perform(
            using: preview,
            userConfirmed: true,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test"
        )

        XCTAssertEqual(performed.exitCode, 0)
        XCTAssertEqual(runner.prunedContext, "colima")
        XCTAssertFalse(runner.invocations.contains { $0.displayCommand == "docker builder prune --force" })
    }

    func testDockerPreviewRejectsUnsafeContextBeforeInventoryOrPrune() {
        let runner = RecordingMaintenanceRunner(dockerContext: "../../remote")
        let executor = NativeMaintenanceExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 2),
            now: { Date(timeIntervalSince1970: 100) }
        )

        let preview = executor.preview(
            action: .dockerBuilderPrune,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test"
        )
        let performed = executor.perform(
            using: preview,
            userConfirmed: true,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test"
        )

        XCTAssertNil(preview.receipt.exitCode)
        XCTAssertTrue(preview.receipt.skippedReason?.localizedCaseInsensitiveContains("context") ?? false)
        XCTAssertNil(performed.exitCode)
        XCTAssertEqual(runner.invocations.map(\.displayCommand), ["docker context show"])
    }

    func testDockerPreviewRejectsChangedExpectedContextBeforeInventoryOrPrune() {
        let runner = RecordingMaintenanceRunner(dockerContext: "remote-production")
        let executor = NativeMaintenanceExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 2),
            now: { Date(timeIntervalSince1970: 100) }
        )

        let preview = executor.preview(
            action: .dockerBuilderPrune,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test",
            contextName: "colima"
        )
        let performed = executor.perform(
            using: preview,
            userConfirmed: true,
            findingPath: "/Users/test/.colima/default",
            ruleVersion: "rules-test",
            contextName: "colima"
        )

        XCTAssertNil(preview.receipt.exitCode)
        XCTAssertTrue(preview.receipt.skippedReason?.localizedCaseInsensitiveContains("context") ?? false)
        XCTAssertNil(performed.exitCode)
        XCTAssertEqual(runner.invocations.map(\.displayCommand), ["docker context show"])
    }

    func testNpmPreviewCannotAuthorizeDifferentPathOrRuleVersion() {
        let runner = RecordingMaintenanceRunner()
        let executor = NativeMaintenanceExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 2),
            now: { Date(timeIntervalSince1970: 100) }
        )
        let preview = executor.preview(
            action: .npmCacheClean,
            findingPath: "/Users/test/.npm/_cacache",
            ruleVersion: "rules-test"
        )

        let wrongPath = executor.perform(
            using: preview,
            userConfirmed: true,
            findingPath: "/Users/test/.npm/_npx",
            ruleVersion: "rules-test"
        )
        XCTAssertNil(wrongPath.exitCode)
        XCTAssertTrue(wrongPath.skippedReason?.localizedCaseInsensitiveContains("match") ?? false)

        let wrongRule = executor.perform(
            using: preview,
            userConfirmed: true,
            findingPath: "/Users/test/.npm/_cacache",
            ruleVersion: "other-rules"
        )
        XCTAssertNil(wrongRule.exitCode)
        XCTAssertTrue(wrongRule.skippedReason?.localizedCaseInsensitiveContains("match") ?? false)
        XCTAssertEqual(runner.invocations.map(\.displayCommand), ["npm cache verify"])
    }

    func testNativePerformBlocksWhenResolvedExecutableIdentityChanges() {
        let runner = RecordingMaintenanceRunner()
        let resolver = SequenceNativeExecutableResolver(paths: ["/approved/npm-v1", "/approved/npm-v2"])
        let executor = NativeMaintenanceExecutor(
            runner: runner,
            configuration: NativeActionExecutionConfiguration(timeout: 2),
            executableResolver: resolver,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let preview = executor.preview(
            action: .npmCacheClean,
            findingPath: "/Users/test/.npm/_cacache",
            ruleVersion: "rules-test"
        )

        let receipt = executor.perform(
            using: preview,
            userConfirmed: true,
            findingPath: "/Users/test/.npm/_cacache",
            ruleVersion: "rules-test"
        )

        XCTAssertNil(receipt.exitCode)
        XCTAssertTrue(receipt.skippedReason?.localizedCaseInsensitiveContains("identity changed") ?? false)
        XCTAssertEqual(runner.invocations.count, 1)
    }

    func testNativeReceiptBridgePreservesMaintenanceCommandIdentity() {
        let receipt = NativeActionReceipt(
            kind: .npmCacheClean,
            mode: .dryRun,
            commandDisplay: ["npm", "cache", "verify"],
            exitCode: 0,
            stdoutPreview: ["Cache verified"],
            stderrPreview: [],
            beforeDisk: nil,
            afterDisk: nil,
            skippedReason: nil,
            nonClaims: NativeMaintenanceAction.npmCacheClean.nonClaims
        )

        let canonical = NativeMaintenanceReceiptBridge.nativeToolExecutionReceipt(
            from: receipt,
            action: .npmCacheClean,
            ruleVersion: "rules-test",
            findingPath: "/Users/test/.npm",
            userConfirmed: false
        )

        XCTAssertEqual(canonical.command.id, "npm.cache-clean")
        XCTAssertEqual(canonical.status, "dry-run")
        XCTAssertEqual(canonical.invocation?.displayCommand, "npm cache verify")
    }

    func testGuidanceIncludesSafeMaintenanceIdsButKeepsBroadPrunes() throws {
        let docker = Finding(
            scopeName: "fixture",
            path: "/Users/test/.docker",
            displayName: ".docker",
            logicalSize: 100,
            allocatedSize: 100,
            isDirectory: true,
            safetyClass: .reviewRequired,
            actionKind: .nativeToolCommand,
            ruleMatches: [],
            evidence: []
        )
        let npm = Finding(
            scopeName: "fixture",
            path: "/Users/test/.npm",
            displayName: ".npm",
            logicalSize: 100,
            allocatedSize: 100,
            isDirectory: true,
            safetyClass: .safeAfterCondition,
            actionKind: .nativeToolCommand,
            ruleMatches: [],
            evidence: []
        )

        let report = NativeToolGuidance.report(for: [docker, npm], ruleVersion: "rules-test")
        let commandIDs = Set(report.receipts.flatMap { $0.commands.map(\.id) })
        XCTAssertTrue(commandIDs.contains("docker.builder-prune"))
        XCTAssertTrue(commandIDs.contains("docker.prune"))
        XCTAssertTrue(commandIDs.contains("docker.prune-volumes"))
        XCTAssertTrue(commandIDs.contains("npm.cache-clean"))
    }
}

private final class SequenceNativeExecutableResolver: NativeExecutableResolving, @unchecked Sendable {
    private var paths: [String]
    private let lock = NSLock()

    init(paths: [String]) {
        self.paths = paths
    }

    func resolve(_ executable: String) throws -> NativeExecutableResolution {
        lock.lock()
        defer { lock.unlock() }
        let path = paths.count > 1 ? paths.removeFirst() : paths[0]
        return NativeExecutableResolution(launchPath: path, resolvedPath: path, identity: nil)
    }
}

private final class RecordingMaintenanceRunner: ToolCommandRunning, @unchecked Sendable {
    private(set) var invocations: [ToolCommandInvocation] = []
    private let dockerContext: String

    init(dockerContext: String = "colima") {
        self.dockerContext = dockerContext
    }

    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        invocations.append(invocation)
        let stdout: String
        switch invocation.displayCommand {
        case "docker context show": stdout = "\(dockerContext)\n"
        case "docker --context colima system df -v": stdout = "Build cache: 1.0GB\n"
        case "npm cache verify": stdout = "Cache verified\n"
        default: stdout = "maintenance complete\n"
        }
        return ToolCommandOutput(invocation: invocation, exitCode: 0, stdout: stdout)
    }
}

private final class ContextSwitchingMaintenanceRunner: ToolCommandRunning, @unchecked Sendable {
    var ambientContext = "colima"
    private(set) var invocations: [ToolCommandInvocation] = []
    private(set) var prunedContext: String?

    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        invocations.append(invocation)
        if invocation.arguments == ["context", "show"] {
            return ToolCommandOutput(invocation: invocation, exitCode: 0, stdout: "\(ambientContext)\n")
        }
        if invocation.arguments.suffix(3) == ["builder", "prune", "--force"] {
            if invocation.arguments.count >= 2, invocation.arguments[0] == "--context" {
                prunedContext = invocation.arguments[1]
            } else {
                prunedContext = ambientContext
            }
        }
        return ToolCommandOutput(invocation: invocation, exitCode: 0, stdout: "maintenance complete\n")
    }
}
