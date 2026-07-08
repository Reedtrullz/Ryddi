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

public enum RemoteScanCoverageLevel: String, Codable, Hashable, Sendable {
    case complete
    case partial
    case unreachable
    case unsupported
}

public struct RemoteScanCoverage: Codable, Hashable, Sendable {
    public let level: RemoteScanCoverageLevel
    public let successfulCommandIDs: [String]
    public let failedCommandIDs: [String]
    public let timedOutCommandIDs: [String]
    public let permissionDeniedCommandIDs: [String]
    public let explanation: String

    public init(
        level: RemoteScanCoverageLevel,
        successfulCommandIDs: [String],
        failedCommandIDs: [String],
        timedOutCommandIDs: [String],
        permissionDeniedCommandIDs: [String],
        explanation: String
    ) {
        self.level = level
        self.successfulCommandIDs = successfulCommandIDs
        self.failedCommandIDs = failedCommandIDs
        self.timedOutCommandIDs = timedOutCommandIDs
        self.permissionDeniedCommandIDs = permissionDeniedCommandIDs
        self.explanation = explanation
    }
}

public struct RemoteTargetContinuityWarning: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let field: String
    public let previousValue: String
    public let currentValue: String
    public let severity: String

    public init(
        id: String? = nil,
        field: String,
        previousValue: String,
        currentValue: String,
        severity: String
    ) {
        self.id = id ?? field
        self.field = field
        self.previousValue = previousValue
        self.currentValue = currentValue
        self.severity = severity
    }
}

public enum RemoteScanCoverageBuilder {
    public static func build(commands: [RemoteCommandResult], osSummary: String?) -> RemoteScanCoverage {
        guard !commands.isEmpty else {
            return RemoteScanCoverage(
                level: .partial,
                successfulCommandIDs: [],
                failedCommandIDs: [],
                timedOutCommandIDs: [],
                permissionDeniedCommandIDs: [],
                explanation: "No remote command receipts were recorded, so scan coverage cannot be proven complete."
            )
        }

        let successful = commands.filter { $0.exitCode == 0 }.map(\.commandID)
        let timedOut = commands.filter(\.timedOut).map(\.commandID)
        let permissionDenied = commands
            .filter { result in
                result.stderrPreview.contains { $0.localizedCaseInsensitiveContains("permission denied") }
            }
            .map(\.commandID)
        let failed = commands.filter { $0.exitCode != 0 || $0.timedOut }.map(\.commandID)

        if successful.isEmpty {
            return RemoteScanCoverage(
                level: .unreachable,
                successfulCommandIDs: [],
                failedCommandIDs: failed,
                timedOutCommandIDs: timedOut,
                permissionDeniedCommandIDs: permissionDenied,
                explanation: "The target was unreachable or all evidence commands failed."
            )
        }

        if let osSummary, !osSummary.localizedCaseInsensitiveContains("linux") {
            return RemoteScanCoverage(
                level: .unsupported,
                successfulCommandIDs: successful,
                failedCommandIDs: failed,
                timedOutCommandIDs: timedOut,
                permissionDeniedCommandIDs: permissionDenied,
                explanation: "The target responded, but the selected preset is Linux VPS focused."
            )
        }

        if failed.isEmpty {
            return RemoteScanCoverage(
                level: .complete,
                successfulCommandIDs: successful,
                failedCommandIDs: [],
                timedOutCommandIDs: [],
                permissionDeniedCommandIDs: [],
                explanation: "Core remote evidence commands completed."
            )
        }

        return RemoteScanCoverage(
            level: .partial,
            successfulCommandIDs: successful,
            failedCommandIDs: failed,
            timedOutCommandIDs: timedOut,
            permissionDeniedCommandIDs: permissionDenied,
            explanation: "Some remote evidence commands failed, timed out, or lacked permission."
        )
    }
}

public enum RemoteTargetContinuity {
    public static func warnings(
        previous: RemoteTargetReference,
        current: RemoteTargetReference
    ) -> [RemoteTargetContinuityWarning] {
        [
            warning(field: "host", previous: previous.resolvedHost, current: current.resolvedHost),
            warning(field: "user", previous: previous.resolvedUser, current: current.resolvedUser),
            warning(field: "port", previous: previous.resolvedPort.map(String.init), current: current.resolvedPort.map(String.init)),
            warning(field: "fingerprint", previous: previous.fingerprint, current: current.fingerprint)
        ].compactMap { $0 }
    }

    private static func warning(
        field: String,
        previous: String?,
        current: String?
    ) -> RemoteTargetContinuityWarning? {
        let previousValue = normalized(previous)
        let currentValue = normalized(current)
        guard previousValue != currentValue else { return nil }
        guard previousValue != nil || currentValue != nil else { return nil }
        return RemoteTargetContinuityWarning(
            field: field,
            previousValue: previousValue ?? "unknown",
            currentValue: currentValue ?? "unknown",
            severity: "warning"
        )
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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
    public let coverage: RemoteScanCoverage
    public let continuityWarnings: [RemoteTargetContinuityWarning]
    public let nonClaims: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case preset
        case target
        case diskFilesystems
        case inodeFilesystems
        case findings
        case nativeGuidance
        case commands
        case coverage
        case continuityWarnings
        case nonClaims
    }

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
        coverage: RemoteScanCoverage? = nil,
        continuityWarnings: [RemoteTargetContinuityWarning] = [],
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
        self.coverage = coverage ?? RemoteScanCoverageBuilder.build(commands: commands, osSummary: nil)
        self.continuityWarnings = continuityWarnings
        self.nonClaims = nonClaims
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        preset = try container.decode(RemoteScanPreset.self, forKey: .preset)
        target = try container.decode(RemoteTargetReference.self, forKey: .target)
        diskFilesystems = try container.decode([RemoteFilesystemSummary].self, forKey: .diskFilesystems)
        inodeFilesystems = try container.decode([RemoteFilesystemSummary].self, forKey: .inodeFilesystems)
        findings = try container.decode([RemoteStorageFinding].self, forKey: .findings)
        nativeGuidance = try container.decode([RemoteNativeGuidance].self, forKey: .nativeGuidance)
        commands = try container.decode([RemoteCommandResult].self, forKey: .commands)
        coverage = try container.decodeIfPresent(RemoteScanCoverage.self, forKey: .coverage)
            ?? RemoteScanCoverageBuilder.build(commands: commands, osSummary: nil)
        continuityWarnings = try container.decodeIfPresent([RemoteTargetContinuityWarning].self, forKey: .continuityWarnings) ?? []
        nonClaims = try container.decode([String].self, forKey: .nonClaims)
    }
}

public enum RemoteTargetResolverError: LocalizedError {
    case invalidTarget(String)
    case resolutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTarget(let message):
            message
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
        let trimmed: String
        do {
            trimmed = try RemoteTargetInputPolicy.validate(input)
        } catch {
            throw RemoteTargetResolverError.invalidTarget(error.localizedDescription)
        }
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
                    let filenamePattern = patternURL.lastPathComponent
                    urls.append(contentsOf: matches.filter { glob(filenamePattern, matches: $0.lastPathComponent) })
                } else {
                    urls.append(patternURL)
                }
            }
        }
        return urls
    }

    private static func glob(_ pattern: String, matches value: String) -> Bool {
        var regex = "^"
        for character in pattern {
            switch character {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            default:
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regex += "$"
        return value.range(of: regex, options: [.regularExpression]) != nil
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
