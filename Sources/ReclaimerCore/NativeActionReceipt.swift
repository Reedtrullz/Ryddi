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

public enum NativeActionReceiptBridge {
    public static func nativeToolExecutionReceipt(
        from receipt: NativeActionReceipt,
        ruleVersion: String,
        findingPath: String,
        category: String = "Homebrew",
        userConfirmed: Bool
    ) -> NativeToolExecutionReceipt {
        let command = homebrewCommand(for: receipt)
        let invocation = ToolCommandInvocation(
            executable: receipt.commandDisplay.first ?? "brew",
            arguments: Array(receipt.commandDisplay.dropFirst())
        )
        let output = ToolCommandOutput(
            invocation: invocation,
            exitCode: receipt.exitCode,
            stdout: receipt.stdoutPreview.joined(separator: "\n"),
            stderr: receipt.stderrPreview.joined(separator: "\n"),
            launchError: launchError(from: receipt)
        )
        let snapshot = hasCommandOutput(receipt) ? ToolCommandSnapshot(output: output) : nil
        let status = status(for: receipt, userConfirmed: userConfirmed)
        let errors = errors(for: receipt, status: status)

        return NativeToolExecutionReceipt(
            id: receipt.id,
            createdAt: receipt.createdAt,
            ruleVersion: ruleVersion,
            mode: receipt.mode == .dryRun ? .dryRun : .perform,
            status: status,
            findingPath: findingPath,
            category: category,
            command: command,
            invocation: invocation,
            authorizationDigest: command.id == "brew.preview" && status == "dry-run" && snapshot?.status == "ok"
                ? NativeToolExecutor.homebrewCleanupAuthorizationDigest(
                    findingPath: findingPath,
                    ruleVersion: ruleVersion
                )
                : nil,
            beforeFreeBytes: receipt.beforeDisk?.displayFreeBytes,
            afterFreeBytes: receipt.mode == .dryRun ? nil : receipt.afterDisk?.displayFreeBytes,
            output: snapshot,
            userConfirmed: userConfirmed,
            message: message(for: receipt, command: command, invocation: invocation, status: status),
            errors: errors,
            nonClaims: NativeToolExecutor.nonClaims + receipt.nonClaims
        )
    }

    public static var defaultHomebrewFindingPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Homebrew", isDirectory: true)
            .standardizedFileURL
            .path
    }

    public static func homebrewCleanupSelection(findingPath: String) -> NativeToolCommandSelection {
        let command = NativeToolCommand(
            id: "brew.cleanup",
            command: "brew cleanup",
            purpose: "Let Homebrew remove old downloads and outdated package versions.",
            risk: .reclaim,
            requiresReview: true,
            expectedEffect: "Reclaims Homebrew-owned cache and old package artifacts."
        )
        let receipt = NativeToolReceipt(
            findingPath: URL(fileURLWithPath: findingPath).standardizedFileURL.path,
            displayName: "Homebrew cache",
            category: "Homebrew",
            allocatedSize: 0,
            safetyClass: .safeAfterCondition,
            actionKind: .nativeToolCommand,
            status: "preview-required",
            message: "Homebrew cleanup requires a fresh preview and one-time capability in the same process for this path.",
            commands: [command],
            nonClaims: NativeToolExecutor.nonClaims
        )
        return NativeToolCommandSelection(receipt: receipt, command: command)
    }

    private static func homebrewCommand(for receipt: NativeActionReceipt) -> NativeToolCommand {
        switch receipt.mode {
        case .dryRun:
            NativeToolCommand(
                id: "brew.preview",
                command: receipt.commandDisplay.joined(separator: " "),
                purpose: "Preview Homebrew cleanup before deleting cached downloads or old versions.",
                risk: .inspect,
                requiresReview: false,
                expectedEffect: "Shows what Homebrew would remove."
            )
        case .perform:
            NativeToolCommand(
                id: "brew.cleanup",
                command: receipt.commandDisplay.joined(separator: " "),
                purpose: "Let Homebrew remove old downloads and outdated package versions.",
                risk: .reclaim,
                requiresReview: true,
                expectedEffect: "Reclaims Homebrew-owned cache and old package artifacts."
            )
        }
    }

    private static func status(for receipt: NativeActionReceipt, userConfirmed: Bool) -> String {
        if receipt.mode == .perform, !userConfirmed, receipt.exitCode == nil {
            return "blocked"
        }
        if let exitCode = receipt.exitCode {
            if exitCode == 0 {
                return receipt.mode == .dryRun ? "dry-run" : "done"
            }
            return "failed"
        }
        if receipt.skippedReason != nil {
            return userConfirmed ? "failed" : "blocked"
        }
        return receipt.mode == .dryRun ? "dry-run" : "blocked"
    }

    private static func message(
        for receipt: NativeActionReceipt,
        command: NativeToolCommand,
        invocation: ToolCommandInvocation,
        status: String
    ) -> String {
        if let skippedReason = receipt.skippedReason {
            return skippedReason
        }
        switch status {
        case "dry-run":
            return "Homebrew dry run completed: \(invocation.displayCommand)"
        case "done":
            return "Homebrew cleanup completed: \(invocation.displayCommand)"
        case "failed":
            return "Homebrew command did not complete successfully: \(invocation.displayCommand)"
        default:
            return "Homebrew native command receipt for \(command.id)."
        }
    }

    private static func errors(for receipt: NativeActionReceipt, status: String) -> [String] {
        var output: [String] = []
        if let skippedReason = receipt.skippedReason {
            output.append(skippedReason)
        }
        if let exitCode = receipt.exitCode, exitCode != 0 {
            output.append("Command exited with status \(exitCode).")
        }
        if status == "failed", output.isEmpty {
            output.append("Command failed.")
        }
        return output
    }

    private static func launchError(from receipt: NativeActionReceipt) -> String? {
        guard receipt.exitCode == nil, let skippedReason = receipt.skippedReason else {
            return nil
        }
        return skippedReason
    }

    private static func hasCommandOutput(_ receipt: NativeActionReceipt) -> Bool {
        receipt.exitCode != nil
            || !receipt.stdoutPreview.isEmpty
            || !receipt.stderrPreview.isEmpty
            || launchError(from: receipt) != nil
    }
}

public struct NativeActionExecutionConfiguration: Hashable, Sendable {
    public let timeout: TimeInterval
    public let diskStatusPath: URL
    public let previewLineLimit: Int
    public let previewAuthorizationAge: TimeInterval

    public init(
        timeout: TimeInterval = 60,
        diskStatusPath: URL = URL(fileURLWithPath: "/System/Volumes/Data"),
        previewLineLimit: Int = 12,
        previewAuthorizationAge: TimeInterval = NativeToolExecutionConfiguration.maximumPreviewAuthorizationAge
    ) {
        self.timeout = max(1, min(timeout, 600))
        self.diskStatusPath = diskStatusPath.standardizedFileURL
        self.previewLineLimit = max(1, min(previewLineLimit, 50))
        self.previewAuthorizationAge = max(
            1,
            min(previewAuthorizationAge, NativeToolExecutionConfiguration.maximumPreviewAuthorizationAge)
        )
    }
}

public struct NativeHomebrewCleanupPreview: @unchecked Sendable {
    public let receipt: NativeActionReceipt
    fileprivate let capability: NativeHomebrewCleanupCapability?

    fileprivate init(receipt: NativeActionReceipt, capability: NativeHomebrewCleanupCapability?) {
        self.receipt = receipt
        self.capability = capability
    }
}

fileprivate final class NativeHomebrewCleanupCapability: @unchecked Sendable {
    let id: UUID
    let executorID: UUID
    let issuedAt: Date
    let ruleVersion: String
    let findingPath: String

    init(executorID: UUID, issuedAt: Date, ruleVersion: String, findingPath: String) {
        self.id = UUID()
        self.executorID = executorID
        self.issuedAt = issuedAt
        self.ruleVersion = ruleVersion
        self.findingPath = findingPath
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
    private let now: @Sendable () -> Date
    private let executorID = UUID()
    private let capabilityLock = NSLock()
    private var outstandingCapabilities: [UUID: NativeHomebrewCleanupCapability] = [:]

    public init(
        runner: any ToolCommandRunning = ProcessToolCommandRunner(),
        diskStatusReader: DiskStatusReader = DiskStatusReader(),
        configuration: NativeActionExecutionConfiguration = NativeActionExecutionConfiguration(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runner = runner
        self.diskStatusReader = diskStatusReader
        self.configuration = configuration
        self.now = now
    }

    public func executeHomebrewCleanup(
        mode: SafeActionExecutionMode,
        userConfirmed: Bool,
        authorization: NativeToolPerformAuthorization? = nil,
        ruleVersion: String = "source",
        findingPath: String = NativeActionReceiptBridge.defaultHomebrewFindingPath
    ) -> NativeActionReceipt {
        _ = authorization
        _ = ruleVersion
        _ = findingPath
        let invocation = homebrewCleanupInvocation(mode: mode)
        let before = diskStatusReader.snapshot(for: configuration.diskStatusPath)

        if mode == .perform, !userConfirmed {
            return skippedHomebrewReceipt(
                mode: mode,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: "Homebrew cleanup requires explicit confirmation."
            )
        }
        if mode == .perform {
            return skippedHomebrewReceipt(
                mode: mode,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: "Homebrew cleanup requires an executor-minted same-process preview capability. Saved receipts and digests are evidence only."
            )
        }
        return runHomebrewCleanup(mode: .dryRun, before: before)
    }

    public func previewHomebrewCleanup(
        ruleVersion: String = "source",
        findingPath: String = NativeActionReceiptBridge.defaultHomebrewFindingPath
    ) -> NativeHomebrewCleanupPreview {
        let receipt = executeHomebrewCleanup(mode: .dryRun, userConfirmed: false)
        guard receipt.exitCode == 0, receipt.skippedReason == nil else {
            return NativeHomebrewCleanupPreview(receipt: receipt, capability: nil)
        }

        let capability = NativeHomebrewCleanupCapability(
            executorID: executorID,
            issuedAt: now(),
            ruleVersion: ruleVersion,
            findingPath: URL(fileURLWithPath: findingPath).standardizedFileURL.path
        )
        capabilityLock.lock()
        outstandingCapabilities[capability.id] = capability
        capabilityLock.unlock()
        return NativeHomebrewCleanupPreview(receipt: receipt, capability: capability)
    }

    public func performHomebrewCleanup(
        using preview: NativeHomebrewCleanupPreview,
        userConfirmed: Bool,
        ruleVersion: String = "source",
        findingPath: String = NativeActionReceiptBridge.defaultHomebrewFindingPath
    ) -> NativeActionReceipt {
        let invocation = homebrewCleanupInvocation(mode: .perform)
        let before = diskStatusReader.snapshot(for: configuration.diskStatusPath)
        guard userConfirmed else {
            return skippedHomebrewReceipt(
                mode: .perform,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: "Homebrew cleanup requires explicit confirmation."
            )
        }
        guard let capability = preview.capability else {
            return skippedHomebrewReceipt(
                mode: .perform,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: "Homebrew cleanup requires a successful same-process preview from this executor."
            )
        }
        let normalizedPath = URL(fileURLWithPath: findingPath).standardizedFileURL.path
        guard capability.executorID == executorID,
              capability.ruleVersion == ruleVersion,
              capability.findingPath == normalizedPath else {
            return skippedHomebrewReceipt(
                mode: .perform,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: "Homebrew preview capability does not match this cleanup request."
            )
        }
        let age = now().timeIntervalSince(capability.issuedAt)
        guard age >= 0, age <= configuration.previewAuthorizationAge else {
            return skippedHomebrewReceipt(
                mode: .perform,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: "Homebrew preview capability is stale; run a new preview."
            )
        }

        capabilityLock.lock()
        let mintedCapability = outstandingCapabilities.removeValue(forKey: capability.id)
        capabilityLock.unlock()
        guard mintedCapability === capability else {
            return skippedHomebrewReceipt(
                mode: .perform,
                commandDisplay: displayCommandParts(for: invocation),
                before: before,
                reason: "Homebrew preview capability has already been used or does not belong to this executor."
            )
        }
        return runHomebrewCleanup(mode: .perform, before: before)
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

    private func runHomebrewCleanup(mode: SafeActionExecutionMode, before: DiskStatusSnapshot) -> NativeActionReceipt {
        let invocation = homebrewCleanupInvocation(mode: mode)
        let output = runner.run(invocation, timeout: configuration.timeout)
        let snapshot = ToolCommandSnapshot(output: output, previewLineLimit: configuration.previewLineLimit)
        let after = output.succeeded && mode == .perform ? diskStatusReader.snapshot(for: configuration.diskStatusPath) : nil
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

    private func displayCommandParts(for invocation: ToolCommandInvocation) -> [String] {
        [invocation.executable] + invocation.arguments
    }
}
