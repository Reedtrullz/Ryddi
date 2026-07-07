import Foundation

public enum RemoteScanPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case vpsGeneral = "vps-general"
}

public struct RemoteTargetReference: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let input: String
    public let alias: String?
    public let resolvedUser: String?
    public let resolvedHost: String?
    public let resolvedPort: Int?
    public let knownHostsState: String
    public let fingerprint: String?

    public init(
        id: String? = nil,
        input: String,
        alias: String? = nil,
        resolvedUser: String? = nil,
        resolvedHost: String? = nil,
        resolvedPort: Int? = nil,
        knownHostsState: String = "unknown",
        fingerprint: String? = nil
    ) {
        self.id = id ?? alias ?? input
        self.input = input
        self.alias = alias
        self.resolvedUser = resolvedUser
        self.resolvedHost = resolvedHost
        self.resolvedPort = resolvedPort
        self.knownHostsState = knownHostsState
        self.fingerprint = fingerprint
    }
}

public struct RemoteCommandResult: Codable, Hashable, Sendable {
    public let commandID: String
    public let displayCommand: String
    public let exitCode: Int32?
    public let timedOut: Bool
    public let stdoutPreview: [String]
    public let stderrPreview: [String]
    public let redactionApplied: Bool

    public init(
        commandID: String,
        displayCommand: String,
        exitCode: Int32?,
        timedOut: Bool,
        stdoutPreview: [String],
        stderrPreview: [String],
        redactionApplied: Bool
    ) {
        self.commandID = commandID
        self.displayCommand = displayCommand
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.stdoutPreview = stdoutPreview
        self.stderrPreview = stderrPreview
        self.redactionApplied = redactionApplied
    }

    public init(commandID: String, output: ToolCommandOutput, redactionApplied: Bool = false) {
        self.init(
            commandID: commandID,
            displayCommand: output.invocation.displayCommand,
            exitCode: output.exitCode,
            timedOut: output.timedOut,
            stdoutPreview: Self.previewLines(output.stdout),
            stderrPreview: Self.previewLines(output.stderr),
            redactionApplied: redactionApplied
        )
    }

    static func previewLines(_ text: String, limit: Int = 12) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(limit)
            .map { $0 }
    }
}

public struct RemoteFilesystemSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(filesystem):\(mount)" }
    public let mount: String
    public let filesystem: String
    public let usedBytes: Int64?
    public let availableBytes: Int64?
    public let capacityPercent: Int?

    public init(mount: String, filesystem: String, usedBytes: Int64?, availableBytes: Int64?, capacityPercent: Int?) {
        self.mount = mount
        self.filesystem = filesystem
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.capacityPercent = capacityPercent
    }
}

public struct RemoteStorageFinding: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let remotePath: String
    public let displayPath: String
    public let bucket: String
    public let allocatedBytes: Int64?
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let evidence: [Evidence]
    public let recommendedNextAction: ReviewNextAction

    public init(
        id: String? = nil,
        remotePath: String,
        displayPath: String,
        bucket: String,
        allocatedBytes: Int64?,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        evidence: [Evidence],
        recommendedNextAction: ReviewNextAction
    ) {
        self.id = id ?? "\(bucket):\(remotePath)"
        self.remotePath = remotePath
        self.displayPath = displayPath
        self.bucket = bucket
        self.allocatedBytes = allocatedBytes
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.evidence = evidence
        self.recommendedNextAction = recommendedNextAction
    }
}

public struct RemoteNativeGuidance: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let command: String
    public let risk: String
    public let summary: String

    public init(id: String, title: String, command: String, risk: String, summary: String) {
        self.id = id
        self.title = title
        self.command = command
        self.risk = risk
        self.summary = summary
    }
}

public struct RemoteProbeReport: Codable, Hashable, Identifiable, Sendable {
    public static let defaultNonClaims = [
        "Remote probe runs read-only commands only.",
        "Ryddi does not store SSH private keys, passwords, or sudo credentials.",
        "Sudo status is a capability probe only; it is not cleanup permission.",
        "Host metadata and command previews stay local unless you export them."
    ]

    public let id: String
    public let createdAt: Date
    public let target: RemoteTargetReference
    public let osSummary: String?
    public let homeDirectory: String?
    public let sudoNonInteractive: Bool?
    public let availableTools: [String]
    public let commands: [RemoteCommandResult]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        target: RemoteTargetReference,
        osSummary: String?,
        homeDirectory: String?,
        sudoNonInteractive: Bool?,
        availableTools: [String],
        commands: [RemoteCommandResult],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.target = target
        self.osSummary = osSummary
        self.homeDirectory = homeDirectory
        self.sudoNonInteractive = sudoNonInteractive
        self.availableTools = availableTools
        self.commands = commands
        self.nonClaims = nonClaims
    }
}

public struct RemoteScanReport: Codable, Hashable, Identifiable, Sendable {
    public static let defaultNonClaims = [
        "No cleanup was executed on the remote target.",
        "Remote scan does not grant permissions, sudo rights, or cleanup approval.",
        "Remote reclaim estimates are native-tool evidence, not exact free-space promises.",
        "Docker volumes, databases, backups, credentials, app data, and unknown state remain preserve/review by default."
    ]

    public let id: String
    public let createdAt: Date
    public let preset: RemoteScanPreset
    public let target: RemoteTargetReference
    public let diskFilesystems: [RemoteFilesystemSummary]
    public let inodeFilesystems: [RemoteFilesystemSummary]
    public let findings: [RemoteStorageFinding]
    public let nativeGuidance: [RemoteNativeGuidance]
    public let commands: [RemoteCommandResult]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        preset: RemoteScanPreset,
        target: RemoteTargetReference,
        diskFilesystems: [RemoteFilesystemSummary],
        inodeFilesystems: [RemoteFilesystemSummary],
        findings: [RemoteStorageFinding],
        nativeGuidance: [RemoteNativeGuidance],
        commands: [RemoteCommandResult],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.preset = preset
        self.target = target
        self.diskFilesystems = diskFilesystems
        self.inodeFilesystems = inodeFilesystems
        self.findings = findings
        self.nativeGuidance = nativeGuidance
        self.commands = commands
        self.nonClaims = nonClaims
    }
}

public enum RemoteTargetResolverError: LocalizedError {
    case resolutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .resolutionFailed(let message):
            message
        }
    }
}

public final class RemoteTargetResolver: @unchecked Sendable {
    private let configURL: URL
    private let knownHostsURL: URL
    private let runner: any ToolCommandRunning

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config"),
        knownHostsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/known_hosts"),
        runner: any ToolCommandRunning = ProcessToolCommandRunner()
    ) {
        self.configURL = configURL.standardizedFileURL
        self.knownHostsURL = knownHostsURL.standardizedFileURL
        self.runner = runner
    }

    public func targets() -> [RemoteTargetReference] {
        Self.parseHostAliases(configURL: configURL)
            .map {
                RemoteTargetReference(input: $0, alias: $0)
            }
    }

    public func resolve(_ input: String) throws -> RemoteTargetReference {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = runner.run(ToolCommandInvocation(executable: "/usr/bin/ssh", arguments: ["-G", trimmed]), timeout: 5)
        guard output.succeeded else {
            let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RemoteTargetResolverError.resolutionFailed(message.isEmpty ? "Could not resolve SSH target \(trimmed)." : message)
        }
        let fields = Self.parseSSHConfigDump(output.stdout)
        let host = fields["hostname"] ?? trimmed
        let port = fields["port"].flatMap(Int.init)
        let knownHost = knownHostState(host: host, port: port)
        let alias = targets().contains { $0.input == trimmed } ? trimmed : nil
        return RemoteTargetReference(
            input: trimmed,
            alias: alias,
            resolvedUser: fields["user"],
            resolvedHost: host,
            resolvedPort: port,
            knownHostsState: knownHost.state,
            fingerprint: knownHost.fingerprint
        )
    }

    public static func parseHostAliases(configURL: URL, fileManager: FileManager = .default) -> [String] {
        let urls = ([configURL] + includeURLs(from: configURL, fileManager: fileManager)).map(\.standardizedFileURL)
        var aliases: [String] = []
        for url in urls where fileManager.fileExists(atPath: url.path) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline).map(String.init) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.localizedCaseInsensitiveCompare("Host") != .orderedSame else { continue }
                guard trimmed.lowercased().hasPrefix("host ") else { continue }
                let values = trimmed.dropFirst(5)
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
                    .filter { !$0.contains("*") && !$0.contains("?") && !$0.hasPrefix("!") }
                aliases.append(contentsOf: values)
            }
        }
        var seen = Set<String>()
        return aliases.filter { seen.insert($0).inserted }.sorted()
    }

    public static func parseSSHConfigDump(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            let pieces = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
            guard pieces.count == 2 else { continue }
            result[pieces[0].lowercased()] = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func includeURLs(from configURL: URL, fileManager: FileManager) -> [URL] {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }
        let base = configURL.deletingLastPathComponent()
        var urls: [URL] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("include ") else { continue }
            let patterns = trimmed.dropFirst(8).split(whereSeparator: \.isWhitespace).map(String.init)
            for pattern in patterns {
                let expanded = expandTilde(pattern)
                let patternURL = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded)
                if patternURL.path.contains("*") {
                    let matches = (try? fileManager.contentsOfDirectory(
                        at: patternURL.deletingLastPathComponent(),
                        includingPropertiesForKeys: nil
                    )) ?? []
                    let suffix = patternURL.lastPathComponent.replacingOccurrences(of: "*", with: "")
                    urls.append(contentsOf: matches.filter { $0.lastPathComponent.hasSuffix(suffix) })
                } else {
                    urls.append(patternURL)
                }
            }
        }
        return urls
    }

    private func knownHostState(host: String, port: Int?) -> (state: String, fingerprint: String?) {
        guard let text = try? String(contentsOf: knownHostsURL, encoding: .utf8) else {
            return ("unknown", nil)
        }
        let hostTokens = [host, port.map { "[\(host)]:\($0)" }].compactMap { $0 }
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3 else { continue }
            let hosts = fields[0].split(separator: ",").map(String.init)
            guard hosts.contains(where: { hostTokens.contains($0) }) else { continue }
            return ("known", "\(fields[1]):\(String(fields[2].prefix(12)))")
        }
        return ("unknown", nil)
    }

    private static func expandTilde(_ value: String) -> String {
        guard value == "~" || value.hasPrefix("~/") else { return value }
        return FileManager.default.homeDirectoryForCurrentUser.path + String(value.dropFirst())
    }
}
