import Foundation

public protocol OpenFileChecking: Sendable {
    func status(for url: URL) -> OpenFileStatus
}

public struct LsofOpenFileChecker: OpenFileChecking {
    public init() {}

    public func status(for url: URL) -> OpenFileStatus {
        let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard FileManager.default.isExecutableFile(atPath: lsof.path) else {
            return OpenFileStatus(isOpen: false, checkFailed: "lsof was not available.")
        }

        let process = Process()
        process.executableURL = lsof
        process.arguments = arguments(for: url)
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return OpenFileStatus(isOpen: false, checkFailed: "Could not run lsof: \(error.localizedDescription)")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus == 1, data.isEmpty {
            return OpenFileStatus(isOpen: false)
        }

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return OpenFileStatus(isOpen: false, checkFailed: message?.isEmpty == false ? message : "lsof exited with status \(process.terminationStatus).")
        }

        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map(String.init) ?? []
        var processes: [String] = []
        var pid: String?
        var command: String?

        for line in lines {
            if line.hasPrefix("p") {
                pid = String(line.dropFirst())
            } else if line.hasPrefix("c") {
                command = String(line.dropFirst())
            } else if line.hasPrefix("n") {
                let processName = [command, pid.map { "pid \($0)" }].compactMap { $0 }.joined(separator: " ")
                if !processName.isEmpty {
                    processes.append(processName)
                }
            }
        }

        return OpenFileStatus(isOpen: !processes.isEmpty, processSummary: Array(Set(processes)).sorted())
    }

    private func arguments(for url: URL) -> [String] {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return ["-F", "pcn", "+D", url.path]
        }
        return ["-F", "pcn", "--", url.path]
    }
}

public struct NoOpenFilesChecker: OpenFileChecking {
    public init() {}

    public func status(for url: URL) -> OpenFileStatus {
        OpenFileStatus(isOpen: false)
    }
}

public struct StaticOpenFileChecker: OpenFileChecking {
    private let statusesByPath: [String: OpenFileStatus]

    public init(openPaths: Set<String>) {
        self.statusesByPath = Dictionary(uniqueKeysWithValues: openPaths.map {
            ($0, OpenFileStatus(isOpen: true, processSummary: ["fixture pid 1"]))
        })
    }

    public init(openStatuses: [String: OpenFileStatus]) {
        self.statusesByPath = openStatuses
    }

    public func status(for url: URL) -> OpenFileStatus {
        statusesByPath[url.path] ?? OpenFileStatus(isOpen: false)
    }
}
