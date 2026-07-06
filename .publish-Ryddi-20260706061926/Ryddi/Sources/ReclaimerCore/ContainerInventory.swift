import Foundation

public enum ToolInspectionState: String, Codable, CaseIterable, Hashable, Sendable {
    case available
    case missing
    case notRunning
    case failed
    case unsupported

    public var label: String {
        switch self {
        case .available: "Available"
        case .missing: "Missing"
        case .notRunning: "Not running"
        case .failed: "Failed"
        case .unsupported: "Unsupported"
        }
    }
}

public struct ToolInspectionStatus: Codable, Hashable, Sendable {
    public let tool: String
    public let state: ToolInspectionState
    public let message: String

    public init(tool: String, state: ToolInspectionState, message: String) {
        self.tool = tool
        self.state = state
        self.message = message
    }
}

public struct ToolCommandInvocation: Codable, Hashable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var displayCommand: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public struct ToolCommandOutput: Codable, Hashable, Sendable {
    public let invocation: ToolCommandInvocation
    public let exitCode: Int32?
    public let timedOut: Bool
    public let stdout: String
    public let stderr: String
    public let launchError: String?

    public init(
        invocation: ToolCommandInvocation,
        exitCode: Int32?,
        timedOut: Bool = false,
        stdout: String = "",
        stderr: String = "",
        launchError: String? = nil
    ) {
        self.invocation = invocation
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.stdout = stdout
        self.stderr = stderr
        self.launchError = launchError
    }

    public var succeeded: Bool {
        exitCode == 0 && !timedOut && launchError == nil
    }
}

public struct ToolCommandSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let command: String
    public let exitCode: Int32?
    public let timedOut: Bool
    public let status: String
    public let stdoutPreview: [String]
    public let stderrPreview: [String]
    public let launchError: String?

    public init(output: ToolCommandOutput, previewLineLimit: Int = 12) {
        self.id = output.invocation.displayCommand
        self.command = output.invocation.displayCommand
        self.exitCode = output.exitCode
        self.timedOut = output.timedOut
        if output.timedOut {
            self.status = "timed-out"
        } else if output.succeeded {
            self.status = "ok"
        } else {
            self.status = "failed"
        }
        self.stdoutPreview = Self.previewLines(output.stdout, limit: previewLineLimit)
        self.stderrPreview = Self.previewLines(output.stderr, limit: previewLineLimit)
        self.launchError = output.launchError
    }

    private static func previewLines(_ text: String, limit: Int) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(limit)
            .map { $0 }
    }
}

public protocol ToolCommandRunning: Sendable {
    func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput
}

public struct ProcessToolCommandRunner: ToolCommandRunning {
    private let maxOutputBytes: Int

    public init(maxOutputBytes: Int = 512_000) {
        self.maxOutputBytes = maxOutputBytes
    }

    public func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [invocation.executable] + invocation.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdout = OutputAccumulator(maxBytes: maxOutputBytes)
        let stderr = OutputAccumulator(maxBytes: maxOutputBytes)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdout.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderr.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return ToolCommandOutput(
                invocation: invocation,
                exitCode: nil,
                stdout: "",
                stderr: "",
                launchError: error.localizedDescription
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdout.append(stdoutPipe.fileHandleForReading.availableData)
        stderr.append(stderrPipe.fileHandleForReading.availableData)

        return ToolCommandOutput(
            invocation: invocation,
            exitCode: process.terminationStatus,
            timedOut: timedOut,
            stdout: stdout.stringValue,
            stderr: stderr.stringValue
        )
    }
}

private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private var data = Data()
    private var truncated = false

    init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard data.count < maxBytes else {
            truncated = true
            return
        }
        let allowed = maxBytes - data.count
        if chunk.count > allowed {
            data.append(chunk.prefix(allowed))
            truncated = true
        } else {
            data.append(chunk)
        }
    }

    var stringValue: String {
        lock.lock()
        defer { lock.unlock() }
        var text = String(data: data, encoding: .utf8) ?? ""
        if truncated {
            text += "\n[output truncated by Ryddi]\n"
        }
        return text
    }
}

public struct DockerStorageBucket: Codable, Hashable, Identifiable, Sendable {
    public var id: String { type }
    public let type: String
    public let total: Int?
    public let active: Int?
    public let sizeText: String
    public let sizeBytes: Int64?
    public let reclaimableText: String
    public let reclaimableBytes: Int64?

    public init(type: String, total: Int?, active: Int?, sizeText: String, sizeBytes: Int64?, reclaimableText: String, reclaimableBytes: Int64?) {
        self.type = type
        self.total = total
        self.active = active
        self.sizeText = sizeText
        self.sizeBytes = sizeBytes
        self.reclaimableText = reclaimableText
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct DockerContextSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let isCurrent: Bool
    public let endpoint: String?
    public let summary: String

    public init(name: String, isCurrent: Bool, endpoint: String?, summary: String) {
        self.name = name
        self.isCurrent = isCurrent
        self.endpoint = endpoint
        self.summary = summary
    }
}

public struct DockerContainerSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { containerID }
    public let containerID: String
    public let name: String
    public let status: String
    public let sizeText: String

    public init(containerID: String, name: String, status: String, sizeText: String) {
        self.containerID = containerID
        self.name = name
        self.status = status
        self.sizeText = sizeText
    }
}

public struct DockerImageSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { imageID }
    public let repository: String
    public let tag: String
    public let imageID: String
    public let sizeText: String

    public init(repository: String, tag: String, imageID: String, sizeText: String) {
        self.repository = repository
        self.tag = tag
        self.imageID = imageID
        self.sizeText = sizeText
    }
}

public struct DockerVolumeSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let driver: String
    public let scope: String

    public init(name: String, driver: String, scope: String) {
        self.name = name
        self.driver = driver
        self.scope = scope
    }
}

public struct DockerInventory: Codable, Hashable, Sendable {
    public let status: ToolInspectionStatus
    public let storage: [DockerStorageBucket]
    public let contexts: [DockerContextSummary]
    public let containers: [DockerContainerSummary]
    public let images: [DockerImageSummary]
    public let volumes: [DockerVolumeSummary]
    public let commands: [ToolCommandSnapshot]

    public init(
        status: ToolInspectionStatus,
        storage: [DockerStorageBucket],
        contexts: [DockerContextSummary],
        containers: [DockerContainerSummary],
        images: [DockerImageSummary],
        volumes: [DockerVolumeSummary],
        commands: [ToolCommandSnapshot]
    ) {
        self.status = status
        self.storage = storage
        self.contexts = contexts
        self.containers = containers
        self.images = images
        self.volumes = volumes
        self.commands = commands
    }
}

public struct ColimaProfileSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let status: String?
    public let runtime: String?
    public let architecture: String?
    public let cpu: String?
    public let memory: String?
    public let disk: String?

    public init(name: String, status: String?, runtime: String?, architecture: String?, cpu: String?, memory: String?, disk: String?) {
        self.name = name
        self.status = status
        self.runtime = runtime
        self.architecture = architecture
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
    }
}

public struct ColimaInventory: Codable, Hashable, Sendable {
    public let status: ToolInspectionStatus
    public let profiles: [ColimaProfileSummary]
    public let commands: [ToolCommandSnapshot]

    public init(status: ToolInspectionStatus, profiles: [ColimaProfileSummary], commands: [ToolCommandSnapshot]) {
        self.status = status
        self.profiles = profiles
        self.commands = commands
    }
}

public struct ContainerInventoryReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let docker: DockerInventory
    public let colima: ColimaInventory
    public let notes: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        docker: DockerInventory,
        colima: ColimaInventory,
        notes: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.docker = docker
        self.colima = colima
        self.notes = notes
        self.nonClaims = nonClaims
    }

    public var dockerReclaimableBytes: Int64? {
        let values = docker.storage.compactMap(\.reclaimableBytes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}

public final class ContainerInventoryScanner: @unchecked Sendable {
    public static let nonClaims = [
        "Container inventory runs read-only inspection commands only.",
        "No prune, delete, stop, reset, or raw VM-disk command is executed.",
        "Docker reclaimable bytes are native-tool estimates and may not equal APFS free-space gains.",
        "Volumes and VM profiles can contain unique databases or project state and remain review-only."
    ]

    private let runner: ToolCommandRunning
    private let timeout: TimeInterval

    public init(runner: ToolCommandRunning = ProcessToolCommandRunner(), timeout: TimeInterval = 5) {
        self.runner = runner
        self.timeout = timeout
    }

    public func inspect() -> ContainerInventoryReport {
        let docker = inspectDocker()
        let colima = inspectColima()
        var notes = [
            "Use this inventory to decide what needs native Docker or Colima review; Ryddi does not mutate container state.",
            "If a tool is missing or not running, only filesystem scan findings are available for that tool."
        ]
        if docker.status.state == .available, docker.storage.isEmpty {
            notes.append("Docker responded, but `docker system df` did not produce parseable storage rows.")
        }
        if colima.status.state == .available, colima.profiles.isEmpty {
            notes.append("Colima responded, but no profiles were reported.")
        }
        return ContainerInventoryReport(
            docker: docker,
            colima: colima,
            notes: notes,
            nonClaims: Self.nonClaims
        )
    }

    private func inspectDocker() -> DockerInventory {
        let systemDF = run("docker", ["system", "df"])
        var outputs = [systemDF]
        guard systemDF.succeeded else {
            return DockerInventory(
                status: status(for: "Docker", output: systemDF),
                storage: [],
                contexts: [],
                containers: [],
                images: [],
                volumes: [],
                commands: outputs.map { ToolCommandSnapshot(output: $0) }
            )
        }

        let context = run("docker", ["context", "ls"])
        let containers = run("docker", ["ps", "-a", "--size", "--format", "{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Size}}"])
        let images = run("docker", ["images", "--format", "{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"])
        let volumes = run("docker", ["volume", "ls", "--format", "{{.Name}}\t{{.Driver}}\t{{.Scope}}"])
        outputs.append(contentsOf: [context, containers, images, volumes])

        return DockerInventory(
            status: ToolInspectionStatus(tool: "Docker", state: .available, message: "Docker responded to read-only inspection commands."),
            storage: Self.parseDockerSystemDF(systemDF.stdout),
            contexts: context.succeeded ? Self.parseDockerContexts(context.stdout) : [],
            containers: containers.succeeded ? Self.parseDockerContainers(containers.stdout) : [],
            images: images.succeeded ? Self.parseDockerImages(images.stdout) : [],
            volumes: volumes.succeeded ? Self.parseDockerVolumes(volumes.stdout) : [],
            commands: outputs.map { ToolCommandSnapshot(output: $0) }
        )
    }

    private func inspectColima() -> ColimaInventory {
        let json = run("colima", ["list", "--json"])
        var outputs = [json]
        if json.succeeded {
            return ColimaInventory(
                status: ToolInspectionStatus(tool: "Colima", state: .available, message: "Colima responded to `colima list --json`."),
                profiles: Self.parseColimaJSON(json.stdout),
                commands: outputs.map { ToolCommandSnapshot(output: $0) }
            )
        }

        if isMissing(json) {
            return ColimaInventory(
                status: status(for: "Colima", output: json),
                profiles: [],
                commands: outputs.map { ToolCommandSnapshot(output: $0) }
            )
        }

        let text = run("colima", ["list"])
        outputs.append(text)
        guard text.succeeded else {
            return ColimaInventory(
                status: status(for: "Colima", output: text),
                profiles: [],
                commands: outputs.map { ToolCommandSnapshot(output: $0) }
            )
        }

        return ColimaInventory(
            status: ToolInspectionStatus(tool: "Colima", state: .available, message: "Colima responded to `colima list`."),
            profiles: Self.parseColimaList(text.stdout),
            commands: outputs.map { ToolCommandSnapshot(output: $0) }
        )
    }

    private func run(_ executable: String, _ arguments: [String]) -> ToolCommandOutput {
        runner.run(ToolCommandInvocation(executable: executable, arguments: arguments), timeout: timeout)
    }

    private func status(for tool: String, output: ToolCommandOutput) -> ToolInspectionStatus {
        if isMissing(output) {
            return ToolInspectionStatus(tool: tool, state: .missing, message: "\(tool) command was not found on PATH.")
        }
        if output.timedOut {
            return ToolInspectionStatus(tool: tool, state: .failed, message: "\(tool) inspection timed out after \(Int(timeout)) second(s).")
        }
        if isNotRunning(output) {
            return ToolInspectionStatus(tool: tool, state: .notRunning, message: "\(tool) is installed but does not appear to be running or reachable.")
        }
        if isUnsupported(output) {
            return ToolInspectionStatus(tool: tool, state: .unsupported, message: "\(tool) command did not support the requested inspection flag.")
        }
        let message = output.launchError ?? output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return ToolInspectionStatus(tool: tool, state: .failed, message: message.isEmpty ? "\(tool) inspection failed." : message)
    }

    private func isMissing(_ output: ToolCommandOutput) -> Bool {
        let text = combinedOutput(output)
        let executable = output.invocation.executable.lowercased()
        return output.exitCode == 127
            || output.launchError != nil
            || text.contains("/usr/bin/env: \(executable): no such file")
            || text.contains("/usr/bin/env: \(executable): not found")
    }

    private func isNotRunning(_ output: ToolCommandOutput) -> Bool {
        let text = combinedOutput(output)
        return text.contains("cannot connect to the docker daemon")
            || text.contains("is the docker daemon running")
            || text.contains("docker daemon is not running")
            || text.contains("failed to connect to the docker api")
            || text.contains("cannot connect to the docker api")
            || text.contains("connection refused")
            || (output.invocation.executable.lowercased() == "docker" && text.contains("connect: no such file or directory"))
    }

    private func isUnsupported(_ output: ToolCommandOutput) -> Bool {
        let text = combinedOutput(output)
        return text.contains("unknown flag")
            || text.contains("flag provided but not defined")
            || text.contains("unknown shorthand flag")
    }

    private func combinedOutput(_ output: ToolCommandOutput) -> String {
        [output.stderr, output.stdout, output.launchError ?? ""]
            .joined(separator: "\n")
            .lowercased()
    }

    public static func parseDockerSystemDF(_ output: String) -> [DockerStorageBucket] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("type") }
            .compactMap(parseDockerStorageBucket)
    }

    private static func parseDockerStorageBucket(_ line: String) -> DockerStorageBucket? {
        let knownTypes = ["Local Volumes", "Build Cache", "Images", "Containers"]
        guard let type = knownTypes.first(where: { line.hasPrefix($0) }) else { return nil }
        let rest = line.dropFirst(type.count).trimmingCharacters(in: .whitespaces)
        let fields = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 4 else { return nil }
        let reclaimable = fields.dropFirst(3).joined(separator: " ")
        return DockerStorageBucket(
            type: type,
            total: Int(fields[0]),
            active: Int(fields[1]),
            sizeText: fields[2],
            sizeBytes: parseByteCount(fields[2]),
            reclaimableText: reclaimable,
            reclaimableBytes: parseByteCount(fields[3])
        )
    }

    public static func parseDockerContexts(_ output: String) -> [DockerContextSummary] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("name") }
            .compactMap { line in
                let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard let name = fields.first else { return nil }
                let endpoint = fields.first { $0.contains("://") }
                return DockerContextSummary(name: name, isCurrent: fields.contains("*"), endpoint: endpoint, summary: line)
            }
    }

    public static func parseDockerContainers(_ output: String) -> [DockerContainerSummary] {
        tabRows(output).compactMap { fields in
            guard fields.count >= 4 else { return nil }
            return DockerContainerSummary(containerID: fields[0], name: fields[1], status: fields[2], sizeText: fields[3])
        }
    }

    public static func parseDockerImages(_ output: String) -> [DockerImageSummary] {
        tabRows(output).compactMap { fields in
            guard fields.count >= 4 else { return nil }
            return DockerImageSummary(repository: fields[0], tag: fields[1], imageID: fields[2], sizeText: fields[3])
        }
    }

    public static func parseDockerVolumes(_ output: String) -> [DockerVolumeSummary] {
        tabRows(output).compactMap { fields in
            guard fields.count >= 3 else { return nil }
            return DockerVolumeSummary(name: fields[0], driver: fields[1], scope: fields[2])
        }
    }

    public static func parseColimaJSON(_ output: String) -> [ColimaProfileSummary] {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let profiles: [[String: Any]]
        if let array = json as? [[String: Any]] {
            profiles = array
        } else if let dictionary = json as? [String: Any], let array = dictionary["profiles"] as? [[String: Any]] {
            profiles = array
        } else {
            profiles = []
        }
        return profiles.compactMap { dictionary in
            let name = stringValue(dictionary, keys: ["name", "profile"]) ?? "default"
            return ColimaProfileSummary(
                name: name,
                status: stringValue(dictionary, keys: ["status"]),
                runtime: stringValue(dictionary, keys: ["runtime"]),
                architecture: stringValue(dictionary, keys: ["arch", "architecture"]),
                cpu: stringValue(dictionary, keys: ["cpus", "cpu"]),
                memory: stringValue(dictionary, keys: ["memory"]),
                disk: stringValue(dictionary, keys: ["disk", "diskSize"])
            )
        }
    }

    public static func parseColimaList(_ output: String) -> [ColimaProfileSummary] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("profile") && !$0.lowercased().hasPrefix("name") }
            .compactMap { line in
                let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard !fields.isEmpty else { return nil }
                return ColimaProfileSummary(
                    name: fields[safe: 0] ?? "default",
                    status: fields[safe: 1],
                    runtime: fields[safe: 6],
                    architecture: fields[safe: 2],
                    cpu: fields[safe: 3],
                    memory: fields[safe: 4],
                    disk: fields[safe: 5]
                )
            }
    }

    private static func tabRows(_ output: String) -> [[String]] {
        output
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(separator: "\t", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isEmpty) }
    }

    private static func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String {
                return string
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            if let dictionary = value as? [String: Any] {
                if let value = stringValue(dictionary, keys: ["value", "size"]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func parseByteCount(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var number = ""
        var unit = ""
        for character in trimmed {
            if character.isNumber || character == "." {
                number.append(character)
            } else if !character.isWhitespace {
                unit.append(character)
            }
        }
        guard let value = Double(number) else { return nil }
        let normalizedUnit = unit.lowercased().replacingOccurrences(of: "ib", with: "b")
        let multiplier: Double
        switch normalizedUnit {
        case "", "b": multiplier = 1
        case "kb", "k": multiplier = 1_000
        case "mb", "m": multiplier = 1_000_000
        case "gb", "g": multiplier = 1_000_000_000
        case "tb", "t": multiplier = 1_000_000_000_000
        default: return nil
        }
        return Int64(value * multiplier)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
