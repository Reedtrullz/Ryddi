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
        self.beforeFreeBytes = beforeFreeBytes
        self.afterFreeBytes = afterFreeBytes
        self.output = output
        self.userConfirmed = userConfirmed
        self.message = message
        self.errors = errors
        self.nonClaims = nonClaims
    }
}

public struct NativeToolExecutionConfiguration: Hashable, Sendable {
    public let timeout: TimeInterval
    public let diskStatusPath: URL

    public init(
        timeout: TimeInterval = 60,
        diskStatusPath: URL = URL(fileURLWithPath: "/System/Volumes/Data")
    ) {
        self.timeout = max(1, min(timeout, 600))
        self.diskStatusPath = diskStatusPath.standardizedFileURL
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

    public init(
        runner: any ToolCommandRunning = ProcessToolCommandRunner(),
        diskStatusReader: DiskStatusReader = DiskStatusReader(),
        configuration: NativeToolExecutionConfiguration = NativeToolExecutionConfiguration()
    ) {
        self.runner = runner
        self.diskStatusReader = diskStatusReader
        self.configuration = configuration
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

    public func execute(
        selection: NativeToolCommandSelection,
        mode: NativeToolExecutionMode,
        ruleVersion: String,
        userConfirmed: Bool
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

        if let actionCommand = Self.nativeActionCommand(for: command, invocation: invocation),
           let reason = NativeActionAllowlist.validate(actionCommand).blockedReason {
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
