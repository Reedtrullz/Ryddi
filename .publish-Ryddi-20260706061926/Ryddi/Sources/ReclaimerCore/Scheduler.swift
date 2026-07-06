import Foundation

public struct ScheduleConfiguration: Codable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int = 9, minute: Int = 30) {
        self.hour = hour
        self.minute = minute
    }
}

public final class LaunchAgentManager: @unchecked Sendable {
    public let label = "com.reidar.ryddi.agent"
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func plist(cliPath: String, logPath: String, schedule: ScheduleConfiguration = ScheduleConfiguration()) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(cliPath)</string>
            <string>plan</string>
            <string>--json</string>
            <string>--save-audit</string>
          </array>
          <key>StartCalendarInterval</key>
          <dict>
            <key>Hour</key>
            <integer>\(schedule.hour)</integer>
            <key>Minute</key>
            <integer>\(schedule.minute)</integer>
          </dict>
          <key>StandardOutPath</key>
          <string>\(logPath)</string>
          <key>StandardErrorPath</key>
          <string>\(logPath)</string>
        </dict>
        </plist>
        """
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
