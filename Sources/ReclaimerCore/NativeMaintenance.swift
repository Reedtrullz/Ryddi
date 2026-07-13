import CryptoKit
import Foundation

public enum NativeMaintenanceAction: String, Codable, CaseIterable, Hashable, Sendable {
    case dockerBuilderPrune = "docker.builder-prune"
    case npmCacheClean = "npm.cache-clean"

    public var safeActionKind: SafeActionKind {
        switch self {
        case .dockerBuilderPrune: .dockerBuilderPrune
        case .npmCacheClean: .npmCacheClean
        }
    }

    public var previewInvocation: ToolCommandInvocation {
        switch self {
        case .dockerBuilderPrune:
            ToolCommandInvocation(executable: "docker", arguments: ["system", "df", "-v"])
        case .npmCacheClean:
            ToolCommandInvocation(executable: "npm", arguments: ["cache", "verify"])
        }
    }

    public var performInvocation: ToolCommandInvocation {
        switch self {
        case .dockerBuilderPrune:
            ToolCommandInvocation(executable: "docker", arguments: ["builder", "prune", "--force"])
        case .npmCacheClean:
            ToolCommandInvocation(executable: "npm", arguments: ["cache", "clean", "--force"])
        }
    }

    public var previewDescription: String {
        switch self {
        case .dockerBuilderPrune: "Docker system df inventory"
        case .npmCacheClean: "npm cache verify"
        }
    }

    public var nonClaims: [String] {
        switch self {
        case .dockerBuilderPrune:
            return [
                "Docker decides the exact build-cache entries removed.",
                "This action does not remove containers, images, volumes, Colima profiles, or VM disks.",
                "Docker's estimate and the observed APFS free-space delta may differ."
            ]
        case .npmCacheClean:
            return [
                "npm decides the exact cache entries removed.",
                "This action does not remove node_modules, lockfiles, project files, credentials, or npm configuration.",
                "npm's cache size and the observed APFS free-space delta may differ."
            ]
        }
    }
}

public struct NativeMaintenancePreview: Sendable {
    public let action: NativeMaintenanceAction
    public let findingPath: String
    public let ruleVersion: String
    public let contextName: String?
    public let receipt: NativeActionReceipt

    fileprivate let capability: NativeMaintenanceCapability?

    fileprivate init(
        action: NativeMaintenanceAction,
        findingPath: String,
        ruleVersion: String,
        contextName: String?,
        receipt: NativeActionReceipt,
        capability: NativeMaintenanceCapability?
    ) {
        self.action = action
        self.findingPath = findingPath
        self.ruleVersion = ruleVersion
        self.contextName = contextName
        self.receipt = receipt
        self.capability = capability
    }
}

private final class NativeMaintenanceCapability: @unchecked Sendable {
    let id = UUID()
    let executorID: UUID
    let issuedAt: Date
    let action: NativeMaintenanceAction
    let findingPath: String
    let ruleVersion: String
    let contextName: String?
    let previewDigest: String
    let executableResolution: NativeExecutableResolution

    init(
        executorID: UUID,
        issuedAt: Date,
        action: NativeMaintenanceAction,
        findingPath: String,
        ruleVersion: String,
        contextName: String?,
        previewDigest: String,
        executableResolution: NativeExecutableResolution
    ) {
        self.executorID = executorID
        self.issuedAt = issuedAt
        self.action = action
        self.findingPath = findingPath
        self.ruleVersion = ruleVersion
        self.contextName = contextName
        self.previewDigest = previewDigest
        self.executableResolution = executableResolution
    }
}

public final class NativeMaintenanceExecutor: @unchecked Sendable {
    private let runner: any ToolCommandRunning
    private let diskStatusReader: DiskStatusReader
    private let configuration: NativeActionExecutionConfiguration
    private let executableResolver: any NativeExecutableResolving
    private let now: @Sendable () -> Date
    private let executorID = UUID()
    private let capabilityLock = NSLock()
    private var outstandingCapabilities: [UUID: NativeMaintenanceCapability] = [:]

    public init(
        runner: any ToolCommandRunning = ProcessToolCommandRunner(),
        diskStatusReader: DiskStatusReader = DiskStatusReader(),
        configuration: NativeActionExecutionConfiguration = NativeActionExecutionConfiguration(),
        executableResolver: (any NativeExecutableResolving)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runner = runner
        self.diskStatusReader = diskStatusReader
        self.configuration = configuration
        self.executableResolver = executableResolver
            ?? (runner is ProcessToolCommandRunner ? SystemNativeExecutableResolver() : PassthroughNativeExecutableResolver())
        self.now = now
    }

    public func preview(
        action: NativeMaintenanceAction,
        findingPath: String,
        ruleVersion: String,
        contextName: String? = nil
    ) -> NativeMaintenancePreview {
        let normalizedPath = URL(fileURLWithPath: findingPath).standardizedFileURL.path
        let before = diskStatusReader.snapshot(for: configuration.diskStatusPath)
        let executableResolution: NativeExecutableResolution
        do {
            executableResolution = try executableResolver.resolve(action.previewInvocation.executable)
        } catch {
            return failedPreview(
                action: action,
                findingPath: normalizedPath,
                ruleVersion: ruleVersion,
                contextName: contextName,
                before: before,
                invocation: action.previewInvocation,
                output: ToolCommandOutput(invocation: action.previewInvocation, exitCode: nil, launchError: error.localizedDescription),
                message: error.localizedDescription
            )
        }
        let previewInvocation = action.previewInvocation.replacingExecutable(with: executableResolution.launchPath)

        let resolvedContext: String?
        if action == .dockerBuilderPrune {
            let contextOutput = runner.run(
                ToolCommandInvocation(executable: executableResolution.launchPath, arguments: ["context", "show"]),
                timeout: configuration.timeout
            )
            guard contextOutput.succeeded else {
                return failedPreview(
                    action: action,
                    findingPath: normalizedPath,
                    ruleVersion: ruleVersion,
                    contextName: contextName,
                    before: before,
                    invocation: contextOutput.invocation,
                    output: contextOutput,
                    message: "Docker context could not be resolved; no maintenance preview was authorized."
                )
            }
            resolvedContext = contextName ?? contextOutput.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            resolvedContext = nil
        }

        let output = runner.run(previewInvocation, timeout: configuration.timeout)
        let snapshot = ToolCommandSnapshot(output: output, previewLineLimit: configuration.previewLineLimit)
        guard output.succeeded else {
            let receipt = NativeActionReceipt(
                kind: action.safeActionKind,
                mode: .dryRun,
                commandDisplay: displayCommandParts(for: previewInvocation),
                exitCode: output.exitCode,
                stdoutPreview: snapshot.stdoutPreview,
                stderrPreview: snapshot.stderrPreview,
                beforeDisk: before,
                afterDisk: nil,
                skippedReason: output.launchError ?? "Native preview failed.",
                nonClaims: action.nonClaims,
                beforeObservedFreeBytes: before.displayFreeBytes
            )
            return NativeMaintenancePreview(
                action: action,
                findingPath: normalizedPath,
                ruleVersion: ruleVersion,
                contextName: resolvedContext,
                receipt: receipt,
                capability: nil
            )
        }

        let receipt = NativeActionReceipt(
            kind: action.safeActionKind,
            mode: .dryRun,
            commandDisplay: displayCommandParts(for: previewInvocation),
            exitCode: output.exitCode,
            stdoutPreview: snapshot.stdoutPreview,
            stderrPreview: snapshot.stderrPreview,
            beforeDisk: before,
            afterDisk: nil,
            skippedReason: nil,
            nonClaims: action.nonClaims,
            beforeObservedFreeBytes: before.displayFreeBytes
        )
        let digest = previewDigest(
            action: action,
            findingPath: normalizedPath,
            ruleVersion: ruleVersion,
            contextName: resolvedContext,
            receipt: receipt
        )
        let capability = NativeMaintenanceCapability(
            executorID: executorID,
            issuedAt: now(),
            action: action,
            findingPath: normalizedPath,
            ruleVersion: ruleVersion,
            contextName: resolvedContext,
            previewDigest: digest,
            executableResolution: executableResolution
        )
        capabilityLock.lock()
        outstandingCapabilities[capability.id] = capability
        capabilityLock.unlock()

        return NativeMaintenancePreview(
            action: action,
            findingPath: normalizedPath,
            ruleVersion: ruleVersion,
            contextName: resolvedContext,
            receipt: receipt,
            capability: capability
        )
    }

    public func perform(
        using preview: NativeMaintenancePreview,
        userConfirmed: Bool,
        findingPath: String,
        ruleVersion: String,
        contextName: String? = nil
    ) -> NativeActionReceipt {
        let action = preview.action
        let normalizedPath = URL(fileURLWithPath: findingPath).standardizedFileURL.path
        let before = diskStatusReader.snapshot(for: configuration.diskStatusPath)
        let invocation = action.performInvocation.replacingExecutable(with: preview.capability?.executableResolution.launchPath ?? action.performInvocation.executable)

        guard userConfirmed else {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: "Native maintenance requires explicit confirmation.")
        }
        guard let capability = preview.capability else {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: "Native maintenance requires a successful same-process preview.")
        }
        guard capability.executorID == executorID,
              capability.action == action,
              capability.findingPath == normalizedPath,
              capability.ruleVersion == ruleVersion,
              capability.contextName == contextName ?? preview.contextName else {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: "Native preview capability does not match this maintenance request.")
        }
        guard now().timeIntervalSince(capability.issuedAt) >= 0,
              now().timeIntervalSince(capability.issuedAt) <= configuration.previewAuthorizationAge else {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: "Native preview capability is stale; run a new preview.")
        }

        let expectedDigest = previewDigest(
            action: action,
            findingPath: preview.findingPath,
            ruleVersion: preview.ruleVersion,
            contextName: preview.contextName,
            receipt: preview.receipt
        )
        guard expectedDigest == capability.previewDigest else {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: "Native preview evidence changed and cannot authorize maintenance.")
        }

        let currentResolution: NativeExecutableResolution
        do {
            currentResolution = try executableResolver.resolve(action.performInvocation.executable)
        } catch {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: error.localizedDescription)
        }
        guard currentResolution == capability.executableResolution else {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: "Native executable identity changed after preview; run a new preview.")
        }

        capabilityLock.lock()
        let mintedCapability = outstandingCapabilities.removeValue(forKey: capability.id)
        capabilityLock.unlock()
        guard mintedCapability === capability else {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: "Native preview capability has already been used or does not belong to this executor.")
        }
        guard NativeActionAllowlist.validate(NativeActionCommand(
            kind: action.safeActionKind,
            executable: action.performInvocation.executable,
            arguments: invocation.arguments
        )) == .allowed else {
            return skippedReceipt(action: action, mode: .perform, before: before, reason: "Native maintenance command was rejected by the exact argv allowlist.")
        }

        let output = runner.run(invocation, timeout: configuration.timeout)
        let snapshot = ToolCommandSnapshot(output: output, previewLineLimit: configuration.previewLineLimit)
        let after = output.succeeded ? diskStatusReader.snapshot(for: configuration.diskStatusPath) : nil
        return NativeActionReceipt(
            kind: action.safeActionKind,
            mode: .perform,
            commandDisplay: displayCommandParts(for: invocation),
            exitCode: output.exitCode,
            stdoutPreview: snapshot.stdoutPreview,
            stderrPreview: snapshot.stderrPreview,
            beforeDisk: before,
            afterDisk: after,
            skippedReason: output.launchError,
            nonClaims: action.nonClaims,
            beforeObservedFreeBytes: before.displayFreeBytes,
            afterObservedFreeBytes: after?.displayFreeBytes
        )
    }

    private func failedPreview(
        action: NativeMaintenanceAction,
        findingPath: String,
        ruleVersion: String,
        contextName: String?,
        before: DiskStatusSnapshot,
        invocation: ToolCommandInvocation,
        output: ToolCommandOutput,
        message: String
    ) -> NativeMaintenancePreview {
        let snapshot = ToolCommandSnapshot(output: output, previewLineLimit: configuration.previewLineLimit)
        let receipt = NativeActionReceipt(
            kind: action.safeActionKind,
            mode: .dryRun,
            commandDisplay: displayCommandParts(for: invocation),
            exitCode: output.exitCode,
            stdoutPreview: snapshot.stdoutPreview,
            stderrPreview: snapshot.stderrPreview,
            beforeDisk: before,
            afterDisk: nil,
            skippedReason: message,
            nonClaims: action.nonClaims,
            beforeObservedFreeBytes: before.displayFreeBytes
        )
        return NativeMaintenancePreview(
            action: action,
            findingPath: findingPath,
            ruleVersion: ruleVersion,
            contextName: contextName,
            receipt: receipt,
            capability: nil
        )
    }

    private func skippedReceipt(
        action: NativeMaintenanceAction,
        mode: SafeActionExecutionMode,
        before: DiskStatusSnapshot,
        reason: String
    ) -> NativeActionReceipt {
        let invocation = mode == .dryRun ? action.previewInvocation : action.performInvocation
        return NativeActionReceipt(
            kind: action.safeActionKind,
            mode: mode,
            commandDisplay: displayCommandParts(for: invocation),
            exitCode: nil,
            stdoutPreview: [],
            stderrPreview: [],
            beforeDisk: before,
            afterDisk: nil,
            skippedReason: reason,
            nonClaims: action.nonClaims,
            beforeObservedFreeBytes: before.displayFreeBytes
        )
    }

    private func previewDigest(
        action: NativeMaintenanceAction,
        findingPath: String,
        ruleVersion: String,
        contextName: String?,
        receipt: NativeActionReceipt
    ) -> String {
        let payload = [
            "ryddi.native.maintenance.preview.v1",
            action.rawValue,
            findingPath,
            ruleVersion,
            contextName ?? "no-context",
            receipt.commandDisplay.joined(separator: "\u{001f}"),
            receipt.exitCode.map(String.init) ?? "no-exit",
            receipt.stdoutPreview.joined(separator: "\n"),
            receipt.stderrPreview.joined(separator: "\n")
        ].joined(separator: "\u{001e}")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func displayCommandParts(for invocation: ToolCommandInvocation) -> [String] {
        [URL(fileURLWithPath: invocation.executable).lastPathComponent] + invocation.arguments
    }
}

public enum NativeMaintenanceReceiptBridge {
    public static func nativeToolExecutionReceipt(
        from receipt: NativeActionReceipt,
        action: NativeMaintenanceAction,
        ruleVersion: String,
        findingPath: String,
        category: String = "Native maintenance",
        userConfirmed: Bool
    ) -> NativeToolExecutionReceipt {
        let invocation = ToolCommandInvocation(
            executable: receipt.commandDisplay.first ?? action.performInvocation.executable,
            arguments: Array(receipt.commandDisplay.dropFirst())
        )
        let output = ToolCommandOutput(
            invocation: invocation,
            exitCode: receipt.exitCode,
            stdout: receipt.stdoutPreview.joined(separator: "\n"),
            stderr: receipt.stderrPreview.joined(separator: "\n"),
            launchError: receipt.skippedReason
        )
        let status: String
        if receipt.skippedReason != nil {
            status = "blocked"
        } else if receipt.exitCode == 0 {
            status = receipt.mode == .dryRun ? "dry-run" : "done"
        } else {
            status = "failed"
        }
        let command = NativeToolCommand(
            id: action.rawValue,
            command: invocation.displayCommand,
            purpose: action.previewDescription,
            risk: receipt.mode == .dryRun ? .inspect : .reclaim,
            requiresReview: true,
            expectedEffect: action.nonClaims.first ?? "Native maintenance action."
        )
        let snapshot = ToolCommandSnapshot(output: output)
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
            beforeFreeBytes: receipt.beforeObservedFreeBytes ?? receipt.beforeDisk?.displayFreeBytes,
            afterFreeBytes: receipt.afterObservedFreeBytes ?? receipt.afterDisk?.displayFreeBytes,
            output: output.exitCode == nil && receipt.skippedReason == nil ? nil : snapshot,
            userConfirmed: userConfirmed,
            message: receipt.skippedReason ?? (receipt.mode == .dryRun ? "Native maintenance preview completed." : "Native maintenance completed."),
            errors: receipt.skippedReason.map { [$0] } ?? (receipt.exitCode == 0 ? [] : ["Native maintenance command failed."]),
            nonClaims: NativeToolExecutor.nonClaims + action.nonClaims
        )
    }
}
