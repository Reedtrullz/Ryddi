import CryptoKit
import Foundation

public enum NativeToolExecutionMode: String, Codable, Hashable, Sendable {
    case dryRun
    case perform
}

public struct NativeToolCommandSelection: Codable, Hashable, Sendable {
    public let receipt: NativeToolReceipt
    public let command: NativeToolCommand

    public init(receipt: NativeToolReceipt, command: NativeToolCommand) {
        self.receipt = receipt
        self.command = command
    }
}

public struct NativeToolExecutionReceipt: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let ruleVersion: String
    public let mode: NativeToolExecutionMode
    public let status: String
    public let findingPath: String
    public let category: String
    public let command: NativeToolCommand
    public let invocation: ToolCommandInvocation?
    public let authorizationDigest: String?
    public let beforeFreeBytes: Int64?
    public let afterFreeBytes: Int64?
    public let output: ToolCommandSnapshot?
    public let userConfirmed: Bool
    public let message: String
    public let errors: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        ruleVersion: String,
        mode: NativeToolExecutionMode,
        status: String,
        findingPath: String,
        category: String,
        command: NativeToolCommand,
        invocation: ToolCommandInvocation?,
        authorizationDigest: String? = nil,
        beforeFreeBytes: Int64?,
        afterFreeBytes: Int64?,
        output: ToolCommandSnapshot?,
        userConfirmed: Bool,
        message: String,
        errors: [String] = [],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.ruleVersion = ruleVersion
        self.mode = mode
        self.status = status
        self.findingPath = findingPath
        self.category = category
        self.command = command
        self.invocation = invocation
        self.authorizationDigest = authorizationDigest
        self.beforeFreeBytes = beforeFreeBytes
        self.afterFreeBytes = afterFreeBytes
        self.output = output
        self.userConfirmed = userConfirmed
        self.message = message
        self.errors = errors
        self.nonClaims = nonClaims
    }
}

public struct NativeToolPerformAuthorization: Codable, Hashable, Sendable {
    public let previewReceipt: NativeToolExecutionReceipt

    public init(previewReceipt: NativeToolExecutionReceipt) {
        self.previewReceipt = previewReceipt
    }
}

public struct NativeToolExecutionConfiguration: Hashable, Sendable {
    /// Preview authorization is never valid for more than 15 minutes.
    public static let maximumPreviewAuthorizationAge: TimeInterval = 15 * 60

    public let timeout: TimeInterval
    public let diskStatusPath: URL
    public let previewAuthorizationAge: TimeInterval

    public init(
        timeout: TimeInterval = 60,
        diskStatusPath: URL = URL(fileURLWithPath: "/System/Volumes/Data"),
        previewAuthorizationAge: TimeInterval = Self.maximumPreviewAuthorizationAge
    ) {
        self.timeout = max(1, min(timeout, 600))
        self.diskStatusPath = diskStatusPath.standardizedFileURL
        self.previewAuthorizationAge = max(1, min(previewAuthorizationAge, Self.maximumPreviewAuthorizationAge))
    }
}

public final class NativeToolExecutor: @unchecked Sendable {
    public static let nonClaims = [
        "Native command receipts execute only one explicitly selected native-tool command.",
        "Ryddi does not raw-delete VM disks, package stores, or tool-owned state for native-tool cleanup.",
        "Destructive native commands and placeholder commands remain guidance-only in this execution path.",
        "Free-space deltas are best-effort APFS snapshots and are not promises of exact reclaim."
    ]

    private let runner: any ToolCommandRunning
    private let diskStatusReader: DiskStatusReader
    private let configuration: NativeToolExecutionConfiguration
    private let now: @Sendable () -> Date

    public init(
        runner: any ToolCommandRunning = ProcessToolCommandRunner(),
        diskStatusReader: DiskStatusReader = DiskStatusReader(),
        configuration: NativeToolExecutionConfiguration = NativeToolExecutionConfiguration(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runner = runner
        self.diskStatusReader = diskStatusReader
        self.configuration = configuration
        self.now = now
    }

    public static func selection(
        in report: NativeToolReport,
        commandID: String,
        findingPath: String? = nil
    ) -> NativeToolCommandSelection? {
        let normalizedCommandID = commandID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommandID.isEmpty else { return nil }
        let normalizedFindingPath = findingPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }

        for receipt in report.receipts {
            if let normalizedFindingPath {
                let receiptPath = URL(fileURLWithPath: receipt.findingPath).standardizedFileURL.path
                guard receiptPath == normalizedFindingPath else { continue }
            }
            if let command = receipt.commands.first(where: { $0.id == normalizedCommandID }) {
                return NativeToolCommandSelection(receipt: receipt, command: command)
            }
        }
        return nil
    }

    public static func blockReason(for command: NativeToolCommand) -> String? {
        if command.risk == .destructive {
            return "Ryddi does not execute destructive native commands in v1; run this manually only after separate review."
        }
        if command.command.contains("<") || command.command.contains(">") {
            return "This command contains placeholders and must be edited and run manually."
        }
        if command.id == "swift.bounded-build" {
            return "This is future build-hygiene guidance, not a cleanup command."
        }
        if containsShellMetacharacter(command.command) {
            return "This command contains shell metacharacters and is guidance-only."
        }
        if commandParts(command.command).isEmpty {
            return "This command is empty."
        }
        return nil
    }

    public static func performBlockReason(for command: NativeToolCommand) -> String? {
        if let reason = blockReason(for: command) {
            return reason
        }
        guard let invocation = invocation(for: command) else {
            return "Could not parse native command for execution."
        }
        guard let actionCommand = nativeActionCommand(for: command, invocation: invocation) else {
            return "Native command perform is only available for explicitly allowlisted commands; this command remains guidance-only."
        }
        return NativeActionAllowlist.validate(actionCommand).blockedReason
    }

    public static func savedDryRunReceipt(
        _ receipt: NativeToolExecutionReceipt,
        authorizes selection: NativeToolCommandSelection,
        ruleVersion: String,
        now: Date = Date(),
        maximumAge: TimeInterval = NativeToolExecutionConfiguration.maximumPreviewAuthorizationAge
    ) -> Bool {
        authorizationBlockReason(
            authorization: NativeToolPerformAuthorization(previewReceipt: receipt),
            selection: selection,
            ruleVersion: ruleVersion,
            now: now,
            maximumAge: maximumAge
        ) == nil
    }

    public static func savedDryRunReceiptExists(
        authorizing selection: NativeToolCommandSelection,
        in receipts: [NativeToolExecutionReceipt],
        ruleVersion: String,
        now: Date = Date(),
        maximumAge: TimeInterval = NativeToolExecutionConfiguration.maximumPreviewAuthorizationAge
    ) -> Bool {
        performAuthorization(
            authorizing: selection,
            in: receipts,
            ruleVersion: ruleVersion,
            now: now,
            maximumAge: maximumAge
        ) != nil
    }

    public static func performAuthorization(
        authorizing selection: NativeToolCommandSelection,
        in receipts: [NativeToolExecutionReceipt],
        ruleVersion: String,
        now: Date = Date(),
        maximumAge: TimeInterval = NativeToolExecutionConfiguration.maximumPreviewAuthorizationAge
    ) -> NativeToolPerformAuthorization? {
        receipts.lazy
            .map(NativeToolPerformAuthorization.init(previewReceipt:))
            .first {
                authorizationBlockReason(
                    authorization: $0,
                    selection: selection,
                    ruleVersion: ruleVersion,
                    now: now,
                    maximumAge: maximumAge
                ) == nil
            }
    }

    public func execute(
        selection: NativeToolCommandSelection,
        mode: NativeToolExecutionMode,
        ruleVersion: String,
        userConfirmed: Bool,
        authorization: NativeToolPerformAuthorization? = nil
    ) -> NativeToolExecutionReceipt {
        let receipt = selection.receipt
        let command = selection.command
        let invocation = Self.invocation(for: command)
        let before = diskStatusReader.snapshot(for: configuration.diskStatusPath).displayFreeBytes

        if let reason = Self.blockReason(for: command) {
            return NativeToolExecutionReceipt(
                ruleVersion: ruleVersion,
                mode: mode,
                status: "blocked",
                findingPath: receipt.findingPath,
                category: receipt.category,
                command: command,
                invocation: invocation,
                beforeFreeBytes: before,
                afterFreeBytes: before,
                output: nil,
                userConfirmed: userConfirmed,
                message: reason,
                errors: [reason],
                nonClaims: Self.nonClaims
            )
        }

        guard let invocation else {
            let error = "Could not parse native command for execution."
            return NativeToolExecutionReceipt(
                ruleVersion: ruleVersion,
                mode: mode,
                status: "blocked",
                findingPath: receipt.findingPath,
                category: receipt.category,
                command: command,
                invocation: nil,
                beforeFreeBytes: before,
                afterFreeBytes: before,
                output: nil,
                userConfirmed: userConfirmed,
                message: error,
                errors: [error],
                nonClaims: Self.nonClaims
            )
        }

        if mode == .dryRun,
           command.id == "brew.preview",
           Self.isExactHomebrewPreviewInvocation(invocation) {
            return executeHomebrewPreview(
                selection: selection,
                invocation: invocation,
                ruleVersion: ruleVersion,
                beforeFreeBytes: before
            )
        }

        guard mode == .perform else {
            return NativeToolExecutionReceipt(
                ruleVersion: ruleVersion,
                mode: mode,
                status: "dry-run",
                findingPath: receipt.findingPath,
                category: receipt.category,
                command: command,
                invocation: invocation,
                beforeFreeBytes: before,
                afterFreeBytes: before,
                output: nil,
                userConfirmed: false,
                message: "Dry run only; Ryddi would execute exactly: \(invocation.displayCommand)",
                nonClaims: Self.nonClaims
            )
        }

        guard let actionCommand = Self.nativeActionCommand(for: command, invocation: invocation) else {
            let error = "Native command perform is only available for explicitly allowlisted commands; this command remains guidance-only."
            return NativeToolExecutionReceipt(
                ruleVersion: ruleVersion,
                mode: mode,
                status: "blocked",
                findingPath: receipt.findingPath,
                category: receipt.category,
                command: command,
                invocation: invocation,
                beforeFreeBytes: before,
                afterFreeBytes: before,
                output: nil,
                userConfirmed: userConfirmed,
                message: error,
                errors: [error],
                nonClaims: Self.nonClaims
            )
        }

        if let reason = NativeActionAllowlist.validate(actionCommand).blockedReason {
            return NativeToolExecutionReceipt(
                ruleVersion: ruleVersion,
                mode: mode,
                status: "blocked",
                findingPath: receipt.findingPath,
                category: receipt.category,
                command: command,
                invocation: invocation,
                beforeFreeBytes: before,
                afterFreeBytes: before,
                output: nil,
                userConfirmed: userConfirmed,
                message: reason,
                errors: [reason],
                nonClaims: Self.nonClaims
            )
        }

        guard userConfirmed else {
            let error = "Native command execution requires explicit confirmation."
            return NativeToolExecutionReceipt(
                ruleVersion: ruleVersion,
                mode: mode,
                status: "blocked",
                findingPath: receipt.findingPath,
                category: receipt.category,
                command: command,
                invocation: invocation,
                beforeFreeBytes: before,
                afterFreeBytes: before,
                output: nil,
                userConfirmed: false,
                message: error,
                errors: [error],
                nonClaims: Self.nonClaims
            )
        }

        if let reason = Self.authorizationBlockReason(
            authorization: authorization,
            selection: selection,
            ruleVersion: ruleVersion,
            now: now(),
            maximumAge: configuration.previewAuthorizationAge
        ) {
            return NativeToolExecutionReceipt(
                ruleVersion: ruleVersion,
                mode: mode,
                status: "blocked",
                findingPath: receipt.findingPath,
                category: receipt.category,
                command: command,
                invocation: invocation,
                beforeFreeBytes: before,
                afterFreeBytes: before,
                output: nil,
                userConfirmed: true,
                message: reason,
                errors: [reason],
                nonClaims: Self.nonClaims
            )
        }

        let output = runner.run(invocation, timeout: configuration.timeout)
        let after = diskStatusReader.snapshot(for: configuration.diskStatusPath).displayFreeBytes
        let snapshot = ToolCommandSnapshot(output: output)
        let status = output.succeeded ? "done" : "failed"
        let message = output.succeeded
            ? "Native command completed: \(invocation.displayCommand)"
            : "Native command did not complete successfully: \(invocation.displayCommand)"
        let errors = output.succeeded ? [] : errorMessages(from: output)

        return NativeToolExecutionReceipt(
            ruleVersion: ruleVersion,
            mode: mode,
            status: status,
            findingPath: receipt.findingPath,
            category: receipt.category,
            command: command,
            invocation: invocation,
            beforeFreeBytes: before,
            afterFreeBytes: after,
            output: snapshot,
            userConfirmed: userConfirmed,
            message: message,
            errors: errors,
            nonClaims: Self.nonClaims
        )
    }

    private static func invocation(for command: NativeToolCommand) -> ToolCommandInvocation? {
        let parts = commandParts(command.command)
        guard let executable = parts.first else { return nil }
        let arguments = parts.dropFirst().map(expandTilde)
        return ToolCommandInvocation(executable: expandTilde(executable), arguments: Array(arguments))
    }

    private static func nativeActionCommand(
        for command: NativeToolCommand,
        invocation: ToolCommandInvocation
    ) -> NativeActionCommand? {
        if command.id.hasPrefix("brew.") {
            return NativeActionCommand(
                kind: .homebrewCleanup,
                executable: invocation.executable,
                arguments: invocation.arguments
            )
        }
        return nil
    }

    private func executeHomebrewPreview(
        selection: NativeToolCommandSelection,
        invocation: ToolCommandInvocation,
        ruleVersion: String,
        beforeFreeBytes: Int64?
    ) -> NativeToolExecutionReceipt {
        let output = runner.run(invocation, timeout: configuration.timeout)
        let snapshot = ToolCommandSnapshot(output: output)
        let errors = output.succeeded ? [] : errorMessages(from: output)
        return NativeToolExecutionReceipt(
            createdAt: now(),
            ruleVersion: ruleVersion,
            mode: .dryRun,
            status: output.succeeded ? "dry-run" : "failed",
            findingPath: selection.receipt.findingPath,
            category: selection.receipt.category,
            command: selection.command,
            invocation: invocation,
            authorizationDigest: output.succeeded
                ? Self.homebrewCleanupAuthorizationDigest(
                    findingPath: selection.receipt.findingPath,
                    ruleVersion: ruleVersion
                )
                : nil,
            beforeFreeBytes: beforeFreeBytes,
            afterFreeBytes: beforeFreeBytes,
            output: snapshot,
            userConfirmed: false,
            message: output.succeeded
                ? "Homebrew preview completed: \(invocation.displayCommand)"
                : "Homebrew preview did not complete successfully: \(invocation.displayCommand)",
            errors: errors,
            nonClaims: Self.nonClaims
        )
    }

    static func authorizationBlockReason(
        authorization: NativeToolPerformAuthorization?,
        selection: NativeToolCommandSelection,
        ruleVersion: String,
        now: Date,
        maximumAge: TimeInterval
    ) -> String? {
        guard selection.command.id == "brew.cleanup",
              let performInvocation = invocation(for: selection.command),
              isExactHomebrewCleanupInvocation(performInvocation) else {
            return "No preview authorization scheme exists for this native command."
        }

        guard let authorization else {
            return "Homebrew cleanup requires a fresh successful brew.preview authorization receipt."
        }
        let preview = authorization.previewReceipt
        guard preview.mode == .dryRun,
              preview.status == "dry-run",
              preview.errors.isEmpty,
              preview.command.id == "brew.preview" else {
            return "Homebrew preview authorization is not a clean successful dry-run receipt."
        }
        guard preview.ruleVersion == ruleVersion else {
            return "Homebrew preview authorization was created with a different rule version."
        }
        let plannedPath = URL(fileURLWithPath: selection.receipt.findingPath).standardizedFileURL.path
        let previewPath = URL(fileURLWithPath: preview.findingPath).standardizedFileURL.path
        guard previewPath == plannedPath else {
            return "Homebrew preview authorization belongs to a different finding path."
        }
        let boundedMaximumAge = max(
            1,
            min(maximumAge, NativeToolExecutionConfiguration.maximumPreviewAuthorizationAge)
        )
        let age = now.timeIntervalSince(preview.createdAt)
        guard age >= 0, age <= boundedMaximumAge else {
            return "Homebrew preview authorization is stale; run brew.preview again."
        }
        guard let previewInvocation = preview.invocation,
              isExactHomebrewPreviewInvocation(previewInvocation),
              let output = preview.output,
              output.status == "ok",
              output.exitCode == 0,
              !output.timedOut,
              output.launchError == nil,
              output.command == previewInvocation.displayCommand else {
            return "Homebrew preview authorization lacks exact successful brew cleanup --dry-run output."
        }
        let expectedDigest = authorizationDigest(
            findingPath: plannedPath,
            ruleVersion: ruleVersion,
            performInvocation: performInvocation
        )
        guard preview.authorizationDigest == expectedDigest else {
            return "Homebrew preview authorization does not match the intended cleanup invocation."
        }
        return nil
    }

    public static func homebrewCleanupAuthorizationDigest(
        findingPath: String,
        ruleVersion: String
    ) -> String {
        authorizationDigest(
            findingPath: findingPath,
            ruleVersion: ruleVersion,
            performInvocation: ToolCommandInvocation(executable: "brew", arguments: ["cleanup"])
        )
    }

    private static func authorizationDigest(
        findingPath: String,
        ruleVersion: String,
        performInvocation: ToolCommandInvocation
    ) -> String {
        let executable = URL(fileURLWithPath: performInvocation.executable).lastPathComponent
        let payload = [
            "ryddi.native.homebrew.authorization.v1",
            URL(fileURLWithPath: findingPath).standardizedFileURL.path,
            ruleVersion,
            executable,
            performInvocation.arguments.joined(separator: "\u{001f}")
        ].joined(separator: "\u{001e}")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isExactHomebrewPreviewInvocation(_ invocation: ToolCommandInvocation) -> Bool {
        let executable = URL(fileURLWithPath: invocation.executable).lastPathComponent
        return executable == "brew"
            && (invocation.arguments == ["cleanup", "--dry-run"]
                || invocation.arguments == ["cleanup", "-n"])
    }

    private static func isExactHomebrewCleanupInvocation(_ invocation: ToolCommandInvocation) -> Bool {
        URL(fileURLWithPath: invocation.executable).lastPathComponent == "brew"
            && invocation.arguments == ["cleanup"]
    }

    private static func commandParts(_ command: String) -> [String] {
        command
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func expandTilde(_ value: String) -> String {
        guard value == "~" || value.hasPrefix("~/") else { return value }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if value == "~" {
            return home
        }
        return home + String(value.dropFirst())
    }

    private static func containsShellMetacharacter(_ command: String) -> Bool {
        command.contains { character in
            "|;&$`()".contains(character)
        }
    }

    private func errorMessages(from output: ToolCommandOutput) -> [String] {
        var messages: [String] = []
        if let launchError = output.launchError {
            messages.append(launchError)
        }
        if output.timedOut {
            messages.append("Command timed out.")
        }
        if let exitCode = output.exitCode, exitCode != 0 {
            messages.append("Command exited with status \(exitCode).")
        }
        if messages.isEmpty {
            messages.append("Command failed.")
        }
        return messages
    }
}
