import Foundation

public enum ScheduledReportKind: String, Codable, CaseIterable, Hashable, Sendable {
    case plan
    case evidence

    public var label: String {
        switch self {
        case .plan: return "Dry-run plan"
        case .evidence: return "Evidence report"
        }
    }

    public var commandArguments: [String] {
        switch self {
        case .plan:
            return ["plan", "--json", "--save-audit"]
        case .evidence:
            return ["report", "--json", "--save-report"]
        }
    }
}

public struct ScheduledScopeSelection: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case preset
        case savedScopeSet
    }

    public let kind: Kind
    public let value: String

    public init(preset: ScanScopePreset = .developer) {
        self.kind = .preset
        self.value = preset.rawValue
    }

    public init(savedScopeSet reference: String) {
        self.kind = .savedScopeSet
        self.value = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var commandArguments: [String] {
        switch kind {
        case .preset:
            return ["--preset", value]
        case .savedScopeSet:
            return ["--scope-set", value]
        }
    }

    public var summary: String {
        switch kind {
        case .preset:
            return "Preset: \(value)"
        case .savedScopeSet:
            return "Saved scope set: \(value)"
        }
    }
}

public struct ScheduleConfiguration: Codable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int
    public let reportKind: ScheduledReportKind
    public let scopeSelection: ScheduledScopeSelection
    public let limit: Int
    public let includeUserRules: Bool

    public init(
        hour: Int = 9,
        minute: Int = 30,
        reportKind: ScheduledReportKind = .plan,
        scopeSelection: ScheduledScopeSelection = ScheduledScopeSelection(preset: .developer),
        limit: Int = 80,
        includeUserRules: Bool = false
    ) {
        self.hour = hour
        self.minute = minute
        self.reportKind = reportKind
        self.scopeSelection = scopeSelection
        self.limit = max(1, limit)
        self.includeUserRules = includeUserRules
    }

    public var nonClaims: [String] {
        [
            "Scheduled jobs are report-only; they do not call execute, --yes, prune, reset, or vendor uninstallers.",
            "A scheduled scope selects roots to inspect; it does not make personal files cleanup candidates.",
            "If a saved scope set is renamed or removed, that scheduled run should fail visibly instead of falling back to a broader scan."
        ]
    }

    public func programArguments(cliPath: String) -> [String] {
        var arguments = [cliPath]
        arguments.append(contentsOf: reportKind.commandArguments)
        arguments.append(contentsOf: scopeSelection.commandArguments)
        arguments.append(contentsOf: ["--limit", String(limit)])
        if includeUserRules {
            arguments.append("--include-user-rules")
        }
        return arguments
    }
}

public struct LaunchAgentPreview: Codable, Hashable, Sendable {
    public let label: String
    public let plistPath: String
    public let logPath: String
    public let schedule: ScheduleConfiguration
    public let programArguments: [String]
    public let nonClaims: [String]

    public init(
        label: String,
        plistPath: String,
        logPath: String,
        schedule: ScheduleConfiguration,
        programArguments: [String]
    ) {
        self.label = label
        self.plistPath = plistPath
        self.logPath = logPath
        self.schedule = schedule
        self.programArguments = programArguments
        self.nonClaims = schedule.nonClaims
    }
}

public final class LaunchAgentManager: @unchecked Sendable {
    public let label = "com.reidar.ryddi.agent"
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func plist(cliPath: String, logPath: String, schedule: ScheduleConfiguration = ScheduleConfiguration()) -> String {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": schedule.programArguments(cliPath: cliPath),
            "StartCalendarInterval": [
                "Hour": schedule.hour,
                "Minute": schedule.minute
            ],
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath
        ]
        guard
            let data = try? PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            ),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }

    public func install(cliPath: String, home: URL = FileManager.default.homeDirectoryForCurrentUser, schedule: ScheduleConfiguration = ScheduleConfiguration()) throws -> URL {
        let launchAgents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let logs = home.appendingPathComponent("Library/Logs/mac-disk-reclaimer-agent.log")
        try fileManager.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        let target = launchAgents.appendingPathComponent("\(label).plist")
        try plist(cliPath: cliPath, logPath: logs.path, schedule: schedule).write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    public func uninstall(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let target = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
    }

    public func installedPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public func preview(cliPath: String, home: URL = FileManager.default.homeDirectoryForCurrentUser, schedule: ScheduleConfiguration = ScheduleConfiguration()) -> LaunchAgentPreview {
        let logs = home.appendingPathComponent("Library/Logs/mac-disk-reclaimer-agent.log")
        return LaunchAgentPreview(
            label: label,
            plistPath: installedPath(home: home).path,
            logPath: logs.path,
            schedule: schedule,
            programArguments: schedule.programArguments(cliPath: cliPath)
        )
    }

    public func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let target = installedPath(home: home)
        try runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", target.path])
    }

    public func unload(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        try runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(label)"])
    }

    private func runLaunchctl(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "Ryddi.LaunchAgent",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "launchctl exited with status \(process.terminationStatus)."]
            )
        }
    }
}
