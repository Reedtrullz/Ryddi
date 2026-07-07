import Foundation

public final class RemoteSSHCommandRunner: @unchecked Sendable {
    public static let blockedCommandMessage = "blocked: Ryddi Remote Targets v1 only runs bounded read-only SSH probes."

    private let target: RemoteTargetReference
    private let runner: any ToolCommandRunning
    private let timeout: TimeInterval
    private let connectTimeout: Int

    public init(
        target: RemoteTargetReference,
        runner: any ToolCommandRunning = ProcessToolCommandRunner(),
        timeout: TimeInterval = 15,
        connectTimeout: Int = 10
    ) {
        self.target = target
        self.runner = runner
        self.timeout = max(1, min(timeout, 60))
        self.connectTimeout = max(1, min(connectTimeout, 60))
    }

    public func run(commandID: String, remoteCommand: String) -> RemoteCommandResult {
        let trimmed = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if let blockedReason = Self.blockReason(for: trimmed) {
            return RemoteCommandResult(
                commandID: commandID,
                displayCommand: trimmed,
                exitCode: nil,
                timedOut: false,
                stdoutPreview: [],
                stderrPreview: ["\(Self.blockedCommandMessage) \(blockedReason)"],
                redactionApplied: false
            )
        }

        let invocation = ToolCommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [
                "-T",
                "-o", "BatchMode=yes",
                "-o", "NumberOfPasswordPrompts=0",
                "-o", "StrictHostKeyChecking=yes",
                "-o", "ConnectTimeout=\(connectTimeout)",
                target.input,
                trimmed
            ]
        )
        let output = runner.run(invocation, timeout: timeout)
        return RemoteCommandResult(commandID: commandID, output: output)
    }

    public static func blockReason(for remoteCommand: String) -> String? {
        let command = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return "Empty remote commands are not allowed."
        }
        let normalized = command.lowercased()
        if normalized == "sudo -n true" {
            return nil
        }
        if normalized.contains("sudo ") {
            return "Remote sudo commands are guidance-only except the non-interactive sudo capability probe."
        }
        let destructiveFragments = [
            " prune",
            " reset",
            " delete",
            " -delete",
            " rm ",
            " rmdir ",
            " unlink ",
            " truncate ",
            " mkfs",
            " shred ",
            " dd ",
            " execute "
        ]
        let padded = " \(normalized) "
        if let fragment = destructiveFragments.first(where: { padded.contains($0) }) {
            return "Command contains destructive token `\(fragment.trimmingCharacters(in: .whitespaces))`."
        }
        if normalized.contains("stricthostkeychecking=no") || normalized.contains("numberofpasswordprompts") {
            return "SSH policy options are owned by Ryddi, not remote command strings."
        }
        return nil
    }
}
