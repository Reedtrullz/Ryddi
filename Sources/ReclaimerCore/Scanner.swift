import Foundation

public struct ScanOptions: Hashable, Sendable {
    public let minimumFindingSize: Int64
    public let maximumFindingDepth: Int
    public let measurementDepth: Int
    public let includeOpenFileStatus: Bool

    public init(
        minimumFindingSize: Int64 = 1_000_000,
        maximumFindingDepth: Int = 2,
        measurementDepth: Int = 8,
        includeOpenFileStatus: Bool = false
    ) {
        self.minimumFindingSize = minimumFindingSize
        self.maximumFindingDepth = maximumFindingDepth
        self.measurementDepth = measurementDepth
        self.includeOpenFileStatus = includeOpenFileStatus
    }
}

struct FileMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

public final class FileScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let ruleEngine: RuleEngine
    private let openFileChecker: OpenFileChecking

    public init(
        fileManager: FileManager = .default,
        ruleEngine: RuleEngine? = nil,
        openFileChecker: OpenFileChecking = LsofOpenFileChecker()
    ) throws {
        self.fileManager = fileManager
        self.ruleEngine = try ruleEngine ?? RuleEngine.bundled()
        self.openFileChecker = openFileChecker
    }

    public func scan(scopes: [ScanScope], options: ScanOptions = ScanOptions()) -> [Finding] {
        scopes.flatMap { scan(scope: $0, options: options) }
            .sorted { lhs, rhs in
                if lhs.allocatedSize == rhs.allocatedSize {
                    return lhs.path < rhs.path
                }
                return lhs.allocatedSize > rhs.allocatedSize
            }
    }

    private func scan(scope: ScanScope, options: ScanOptions) -> [Finding] {
        let root = scope.root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return [
                permissionFinding(scope: scope, state: .missing, message: "Path does not exist.")
            ]
        }

        guard fileManager.isReadableFile(atPath: root.path) else {
            return [
                permissionFinding(scope: scope, state: .denied, message: "Path is not readable with current permissions.")
            ]
        }

        if !isDirectory.boolValue {
            return [makeFinding(scope: scope, url: root, depth: 0, options: options)]
        }

        var findings = [makeFinding(scope: scope, url: root, depth: 0, options: options)]
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsPackageDescendants]
        ) else {
            findings.append(permissionFinding(scope: scope, state: .denied, message: "Could not list directory contents."))
            return findings
        }

        for child in children {
            collectFindings(scope: scope, url: child, depth: 1, options: options, findings: &findings)
        }
        return findings
    }

    private func collectFindings(scope: ScanScope, url: URL, depth: Int, options: ScanOptions, findings: inout [Finding]) {
        let finding = makeFinding(scope: scope, url: url, depth: depth, options: options)
        let shouldInclude = depth <= options.maximumFindingDepth
            || finding.allocatedSize >= options.minimumFindingSize
            || !finding.ruleMatches.isEmpty
        if shouldInclude {
            findings.append(finding)
        }

        guard depth < options.maximumFindingDepth else { return }
        guard finding.isDirectory, !finding.isSymbolicLink else { return }
        guard let children = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsPackageDescendants]
        ) else {
            return
        }

        for child in children {
            collectFindings(scope: scope, url: child, depth: depth + 1, options: options, findings: &findings)
        }
    }

    private func makeFinding(scope: ScanScope, url: URL, depth: Int, options: ScanOptions) -> Finding {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        let isDirectory = values?.isDirectory ?? false
        let isSymbolicLink = values?.isSymbolicLink ?? false
        let measurement = measure(url: url, maxDepth: options.measurementDepth)
        let classification = ruleEngine.classify(path: url.path, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink)
        let openStatus = options.includeOpenFileStatus ? openFileChecker.status(for: url) : nil

        var evidence = classification.evidence
        evidence.append(Evidence(kind: "size", message: "Allocated size: \(ByteFormat.string(measurement.allocatedSize)); logical size: \(ByteFormat.string(measurement.logicalSize))."))
        if isSymbolicLink {
            evidence.append(Evidence(kind: "symlink", message: "Symbolic link was not followed."))
        }
        if depth == 0 {
            evidence.append(Evidence(kind: "scope", message: "Scan root: \(scope.name)."))
        }

        return Finding(
            scopeName: scope.name,
            path: url.path,
            displayName: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            modificationDate: values?.contentModificationDate,
            ownerHint: ownerHint(for: url.path),
            safetyClass: classification.safetyClass,
            actionKind: classification.actionKind,
            ruleMatches: classification.matches,
            evidence: evidence,
            openFileStatus: openStatus
        )
    }

    private func permissionFinding(scope: ScanScope, state: PermissionState, message: String) -> Finding {
        Finding(
            scopeName: scope.name,
            path: scope.root.path,
            displayName: scope.root.lastPathComponent,
            logicalSize: 0,
            allocatedSize: 0,
            isDirectory: true,
            safetyClass: .reviewRequired,
            actionKind: .reportOnly,
            ruleMatches: [],
            evidence: [Evidence(kind: state.rawValue, message: message)]
        )
    }

    private func measure(url: URL, maxDepth: Int) -> FileMeasurement {
        guard maxDepth >= 0 else {
            return FileMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }

        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else {
            return FileMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }

        if values.isSymbolicLink == true {
            return FileMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return FileMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1)
        }

        guard maxDepth > 0 else {
            return FileMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return FileMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        for case let child as URL in enumerator {
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            if childValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if childValues.isDirectory == true {
                continue
            }
            logical += Int64(childValues.fileSize ?? 0)
            allocated += Int64(childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return FileMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: count)
    }
}

private let resourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]

private func ownerHint(for path: String) -> String? {
    let lower = path.lowercased()
    if lower.contains("/.codex") || lower.contains("com.openai.codex") { return "Codex" }
    if lower.contains("/.colima") { return "Colima" }
    if lower.contains("/docker") { return "Docker" }
    if lower.contains("/developer/xcode") || lower.contains("/deriveddata") { return "Xcode" }
    if lower.contains("/homebrew") || lower.contains("/.cache/homebrew") { return "Homebrew" }
    if lower.contains("/google/chrome") || lower.contains("/chrome/") { return "Chrome" }
    if lower.contains("/garageband") { return "GarageBand" }
    if lower.contains("/logic") { return "Logic" }
    return nil
}

public enum DefaultScopes {
    public static func developerAgentBloat(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ScanScope] {
        let paths: [(String, URL)] = [
            ("Codex state", home.appendingPathComponent(".codex")),
            ("Codex desktop logs", home.appendingPathComponent("Library/Logs/com.openai.codex")),
            ("Codex app cache", home.appendingPathComponent("Library/Caches/Codex")),
            ("Colima", home.appendingPathComponent(".colima")),
            ("Docker", home.appendingPathComponent(".docker")),
            ("Xcode Developer", home.appendingPathComponent("Library/Developer")),
            ("Homebrew cache", home.appendingPathComponent("Library/Caches/Homebrew")),
            ("npm cache", home.appendingPathComponent(".npm")),
            ("pnpm store", home.appendingPathComponent("Library/pnpm/store")),
            ("Yarn cache", home.appendingPathComponent("Library/Caches/Yarn")),
            ("Cargo cache", home.appendingPathComponent(".cargo")),
            ("Go modules", home.appendingPathComponent("go/pkg/mod")),
            ("Private temp", URL(fileURLWithPath: "/private/tmp"))
        ]
        return paths.compactMap { name, url in
            FileManager.default.fileExists(atPath: url.path) ? ScanScope(name: name, root: url, permissionState: .unknown) : nil
        }
    }
}
