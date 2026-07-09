import Foundation

public struct NativeActionReceipt: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let createdAt: Date
    public let kind: SafeActionKind
    public let mode: SafeActionExecutionMode
    public let commandDisplay: [String]
    public let exitCode: Int32?
    public let stdoutPreview: [String]
    public let stderrPreview: [String]
    public let beforeDisk: DiskStatusSnapshot?
    public let afterDisk: DiskStatusSnapshot?
    public let skippedReason: String?
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        kind: SafeActionKind,
        mode: SafeActionExecutionMode,
        commandDisplay: [String],
        exitCode: Int32?,
        stdoutPreview: [String],
        stderrPreview: [String],
        beforeDisk: DiskStatusSnapshot?,
        afterDisk: DiskStatusSnapshot?,
        skippedReason: String?,
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.mode = mode
        self.commandDisplay = commandDisplay
        self.exitCode = exitCode
        self.stdoutPreview = stdoutPreview
        self.stderrPreview = stderrPreview
        self.beforeDisk = beforeDisk
        self.afterDisk = afterDisk
        self.skippedReason = skippedReason
        self.nonClaims = nonClaims
    }
}

public struct NativeActionExecutionConfiguration: Hashable, Sendable {
    public let timeout: TimeInterval
    public let diskStatusPath: URL
    public let previewLineLimit: Int

    public init(
        timeout: TimeInterval = 60,
        diskStatusPath: URL = URL(fileURLWithPath: "/System/Volumes/Data"),
        previewLineLimit: Int = 12
    ) {
        self.timeout = max(1, min(timeout, 600))
        self.diskStatusPath = diskStatusPath.standardizedFileURL
        self.previewLineLimit = max(1, min(previewLineLimit, 50))
    }
}

public final class NativeActionExecutor: @unchecked Sendable {
    public static let homebrewCleanupNonClaims = [
        "Homebrew decides the exact cleanup set.",
        "APFS free space may differ from command estimates.",
        "Ryddi did not remove arbitrary files."
    ]

    private let runner: any ToolCommandRunning
    private let diskStatusReader: DiskStatusReader
    private let configuration: NativeActionExecutionConfiguration

    public init(
        runner: any ToolCommandRunning = ProcessToolCommandRunner(),
        diskStatusReader: DiskStatusReader = DiskStatusReader(),
        configuration: NativeActionExecutionConfiguration = NativeActionExecutionConfiguration()
    ) {
        self.runner = runner
        self.diskStatusReader = diskStatusReader
        self.configuration = configuration
    }

    public func executeHomebrewCleanup(
        mode: SafeActionExecutionMode,
        userConfirmed: Bool
    ) -> NativeActionReceipt {
        let invocation = homebrewCleanupInvocation(mode: mode)
        let command = NativeActionCommand(
            kind: .homebrewCleanup,
            executable: invocation.executable,
            arguments: invocation.arguments
        )
        let before = diskStatusReader.snapshot(for: configuration.diskStatusPath)

        if mode == .perform, !userConfirmed {
            return skippedHomebrewReceipt(
                mode: mode,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: "Homebrew cleanup requires explicit confirmation."
            )
        }

        if let reason = NativeActionAllowlist.validate(command).blockedReason {
            return skippedHomebrewReceipt(
                mode: mode,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: reason
            )
        }

        let output = runner.run(invocation, timeout: configuration.timeout)
        let snapshot = ToolCommandSnapshot(output: output, previewLineLimit: configuration.previewLineLimit)
        let after = output.succeeded ? diskStatusReader.snapshot(for: configuration.diskStatusPath) : nil

        return NativeActionReceipt(
            kind: .homebrewCleanup,
            mode: mode,
            commandDisplay: displayCommandParts(for: invocation),
            exitCode: output.exitCode,
            stdoutPreview: snapshot.stdoutPreview,
            stderrPreview: snapshot.stderrPreview,
            beforeDisk: before,
            afterDisk: after,
            skippedReason: output.launchError,
            nonClaims: Self.homebrewCleanupNonClaims
        )
    }

    private func homebrewCleanupInvocation(mode: SafeActionExecutionMode) -> ToolCommandInvocation {
        switch mode {
        case .dryRun:
            ToolCommandInvocation(executable: "brew", arguments: ["cleanup", "--dry-run"])
        case .perform:
            ToolCommandInvocation(executable: "brew", arguments: ["cleanup"])
        }
    }

    private func skippedHomebrewReceipt(
        mode: SafeActionExecutionMode,
        commandDisplay: [String],
        before: DiskStatusSnapshot,
        reason: String
    ) -> NativeActionReceipt {
        NativeActionReceipt(
            kind: .homebrewCleanup,
            mode: mode,
            commandDisplay: commandDisplay,
            exitCode: nil,
            stdoutPreview: [],
            stderrPreview: [],
            beforeDisk: before,
            afterDisk: nil,
            skippedReason: reason,
            nonClaims: Self.homebrewCleanupNonClaims
        )
    }

    private func displayCommandParts(for invocation: ToolCommandInvocation) -> [String] {
        [invocation.executable] + invocation.arguments
    }
}
