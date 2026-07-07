import Foundation

public final class RemoteProbeBuilder: @unchecked Sendable {
    public static let commands: [(id: String, command: String)] = [
        ("probe.uname", "uname -srm"),
        ("probe.hostname", "hostname"),
        ("probe.user", "id -un"),
        ("probe.home", "printf \"$HOME\""),
        ("probe.os-release", "test -r /etc/os-release && sed -n '1,40p' /etc/os-release || true"),
        ("probe.df", "df -Pk"),
        ("probe.inodes", "df -Pi"),
        ("probe.tools", "command -v docker journalctl apt-get sudo"),
        ("probe.sudo", "sudo -n true")
    ]

    private let target: RemoteTargetReference
    private let ssh: RemoteSSHCommandRunner

    public init(target: RemoteTargetReference, runner: any ToolCommandRunning = ProcessToolCommandRunner(), timeout: TimeInterval = 15) {
        self.target = target
        self.ssh = RemoteSSHCommandRunner(
            target: target,
            runner: runner,
            timeout: timeout,
            connectTimeout: max(1, min(Int(timeout.rounded(.up)), 10))
        )
    }

    public func probe() -> RemoteProbeReport {
        var commandResults: [RemoteCommandResult] = []
        var rawOutputs: [String: ToolCommandOutput] = [:]
        for item in Self.commands {
            let capture = ssh.runOutput(commandID: item.id, remoteCommand: item.command)
            commandResults.append(capture.result)
            rawOutputs[item.id] = capture.output
        }

        let osRelease = rawOutputs["probe.os-release"]?.stdout ?? ""
        let osSummary = RemoteParsers.parseOSRelease(osRelease)
            ?? rawOutputs["probe.uname"]?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let homeDirectory = rawOutputs["probe.home"]?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let tools = parseTools(rawOutputs["probe.tools"]?.stdout ?? "")
        let sudoNonInteractive = rawOutputs["probe.sudo"]?.exitCode.map { $0 == 0 }

        return RemoteProbeReport(
            target: target,
            osSummary: osSummary?.isEmpty == false ? osSummary : nil,
            homeDirectory: homeDirectory?.isEmpty == false ? homeDirectory : nil,
            sudoNonInteractive: sudoNonInteractive,
            availableTools: tools,
            commands: commandResults,
            nonClaims: RemoteProbeReport.defaultNonClaims
        )
    }

    private func parseTools(_ output: String) -> [String] {
        let values = output
            .split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)).lastPathComponent }
            .filter { !$0.isEmpty }
        return Array(Set(values)).sorted()
    }
}
