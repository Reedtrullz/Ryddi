import Foundation

public protocol OpenFileChecking: Sendable {
    func status(for url: URL) -> OpenFileStatus
}

public protocol LinkAwareOpenFileChecking: OpenFileChecking {
    func status(for url: URL, selectedPaths: [String], knownPaths: [String]) -> OpenFileStatus
}

public struct LsofOpenFileChecker: LinkAwareOpenFileChecking {
    private let linkInspector: FilesystemLinkInspecting

    public init(linkInspector: FilesystemLinkInspecting = FilesystemLinkInspector()) {
        self.linkInspector = linkInspector
    }

    public func status(for url: URL) -> OpenFileStatus {
        status(for: url, selectedPaths: [], knownPaths: [])
    }

    public func status(for url: URL, selectedPaths: [String], knownPaths: [String]) -> OpenFileStatus {
        let rawStatus = rawStatus(for: url)
        guard rawStatus.checkFailed == nil else { return rawStatus }

        let evidence = linkInspector.inspect(
            candidateURL: url,
            plannedIdentity: try? FilesystemIdentity.capture(at: url),
            openStatus: rawStatus,
            selectedPaths: selectedPaths,
            knownPaths: knownPaths
        )
        let sharedOpenWasProven = evidence.sharedOpenIdentityOnly && evidence.blockReason == nil
        return rawStatus.withLinkEvidence(evidence, isOpen: rawStatus.isOpen && !sharedOpenWasProven)
    }

    private func rawStatus(for url: URL) -> OpenFileStatus {
        let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
        let checkInfo = checkMode(for: url)
        guard FileManager.default.isExecutableFile(atPath: lsof.path) else {
            return OpenFileStatus(
                isOpen: false,
                checkFailed: "lsof was not available.",
                checkedRecursively: checkInfo.recursive,
                checkedPath: url.path
            )
        }

        let process = Process()
        process.executableURL = lsof
        process.arguments = checkInfo.arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return OpenFileStatus(
                isOpen: false,
                checkFailed: "Could not run lsof: \(error.localizedDescription)",
                checkedRecursively: checkInfo.recursive,
                checkedPath: url.path
            )
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus == 1, data.isEmpty {
            return OpenFileStatus(isOpen: false, checkedRecursively: checkInfo.recursive, checkedPath: url.path)
        }

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return OpenFileStatus(
                isOpen: false,
                checkFailed: message?.isEmpty == false ? message : "lsof exited with status \(process.terminationStatus).",
                checkedRecursively: checkInfo.recursive,
                checkedPath: url.path
            )
        }

        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map(String.init) ?? []
        var hits: [OpenFileHit] = []
        var pid: String?
        var command: String?

        for line in lines {
            if line.hasPrefix("p") {
                pid = String(line.dropFirst())
            } else if line.hasPrefix("c") {
                command = String(line.dropFirst())
            } else if line.hasPrefix("n") {
                let path = String(line.dropFirst())
                let processName = [command, pid.map { "pid \($0)" }].compactMap { $0 }.joined(separator: " ")
                let identity = try? FilesystemIdentity.capture(at: URL(fileURLWithPath: path))
                hits.append(OpenFileHit(
                    path: path,
                    processSummary: processName.isEmpty ? nil : processName,
                    fileIdentityKey: identity?.fileIdentityKey,
                    identityResolutionFailed: identity?.fileIdentityKey == nil
                ))
            }
        }

        let processes = Array(Set(hits.compactMap(\.processSummary))).sorted()
        return OpenFileStatus(
            isOpen: !hits.isEmpty,
            processSummary: processes,
            checkedRecursively: checkInfo.recursive,
            checkedPath: url.path,
            openHits: hits
        )
    }

    private func checkMode(for url: URL) -> (arguments: [String], recursive: Bool) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return (["-F", "pcn", "+D", url.path], true)
        }
        return (["-F", "pcn", "--", url.path], false)
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
