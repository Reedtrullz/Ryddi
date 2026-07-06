import Foundation

public enum ProjectDependencyPolicyDecision: String, Codable, CaseIterable, Hashable, Sendable {
    case review
    case preserve
    case skipReview

    public var label: String {
        switch self {
        case .review: return "Review normally"
        case .preserve: return "Preserve project"
        case .skipReview: return "Skip project review"
        }
    }

    public var guidance: String {
        switch self {
        case .review:
            return "Saved policy keeps this project in Project Dependencies review with user context."
        case .preserve:
            return "Saved policy marks this project as preserve-by-default; Ryddi still reports evidence but should not suggest cleanup for it."
        case .skipReview:
            return "Saved policy skips this project from Project Dependencies review by default; use --include-policy-skipped to inspect it anyway."
        }
    }
}

public struct ProjectDependencyProjectPolicy: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let projectRootPath: String
    public let projectName: String
    public let decision: ProjectDependencyPolicyDecision
    public let reason: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectRootPath: String,
        projectName: String? = nil,
        decision: ProjectDependencyPolicyDecision,
        reason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let standardizedPath = ProjectDependencyPolicy.standardizedPath(projectRootPath)
        self.id = id
        self.projectRootPath = standardizedPath
        self.projectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? URL(fileURLWithPath: standardizedPath).lastPathComponent
        self.decision = decision
        self.reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ProjectDependencyPolicy: Codable, Hashable, Sendable {
    public static let empty = ProjectDependencyPolicy(projects: [])

    public let projects: [ProjectDependencyProjectPolicy]

    public init(projects: [ProjectDependencyProjectPolicy]) {
        self.projects = Self.deduplicated(projects)
    }

    public func matchingPolicy(forProjectRoot path: String) -> ProjectDependencyProjectPolicy? {
        let standardized = Self.standardizedPath(path)
        return projects.first { $0.projectRootPath == standardized }
    }

    public func policies(decision: ProjectDependencyPolicyDecision) -> [ProjectDependencyProjectPolicy] {
        projects.filter { $0.decision == decision }
    }

    public func setting(
        projectRootPath: String,
        projectName: String? = nil,
        decision: ProjectDependencyPolicyDecision,
        reason: String? = nil,
        updatedAt: Date = Date()
    ) -> ProjectDependencyPolicy {
        let standardized = Self.standardizedPath(projectRootPath)
        let existing = projects.first { $0.projectRootPath == standardized }
        let policy = ProjectDependencyProjectPolicy(
            id: existing?.id ?? UUID().uuidString,
            projectRootPath: standardized,
            projectName: projectName ?? existing?.projectName,
            decision: decision,
            reason: reason,
            createdAt: existing?.createdAt ?? updatedAt,
            updatedAt: updatedAt
        )
        return ProjectDependencyPolicy(projects: projects.filter { $0.projectRootPath != standardized } + [policy])
    }

    public func removing(projectRootPath: String) -> ProjectDependencyPolicy {
        let standardized = Self.standardizedPath(projectRootPath)
        return ProjectDependencyPolicy(projects: projects.filter { $0.projectRootPath != standardized })
    }

    public static func standardizedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath.standardizedFileURLPath
    }

    private static func deduplicated(_ projects: [ProjectDependencyProjectPolicy]) -> [ProjectDependencyProjectPolicy] {
        var seen = Set<String>()
        var output: [ProjectDependencyProjectPolicy] = []
        for project in projects.sorted(by: { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.projectRootPath < rhs.projectRootPath
            }
            return lhs.updatedAt > rhs.updatedAt
        }) {
            guard seen.insert(project.projectRootPath).inserted else { continue }
            output.append(project)
        }
        return output.sorted { lhs, rhs in
            if lhs.decision == rhs.decision {
                return lhs.projectRootPath < rhs.projectRootPath
            }
            return lhs.decision.rawValue < rhs.decision.rawValue
        }
    }
}

public struct ProjectDependencyPolicyDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultNonClaims = [
        "Importing this file changes only Ryddi's local Project Dependencies review policy.",
        "Project policy import does not delete files, execute cleanup, grant cleanup permission, or prove that paths still exist.",
        "Project policy exports can contain private local project paths and user-entered reasons; review before sharing."
    ]

    public let schemaVersion: Int
    public let id: String
    public let exportedAt: Date
    public let projects: [ProjectDependencyProjectPolicy]
    public let nonClaims: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String = UUID().uuidString,
        exportedAt: Date = Date(),
        projects: [ProjectDependencyProjectPolicy],
        nonClaims: [String] = Self.defaultNonClaims
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.exportedAt = exportedAt
        self.projects = ProjectDependencyPolicy(projects: projects).projects
        self.nonClaims = nonClaims
    }

    public var policy: ProjectDependencyPolicy {
        ProjectDependencyPolicy(projects: projects)
    }
}

public struct ProjectDependencyPolicyImportResult: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let policyPath: String
    public let mode: String
    public let importedProjectCount: Int
    public let finalProjectCount: Int
    public let policy: ProjectDependencyPolicy
    public let nonClaims: [String]

    public init(
        sourcePath: String,
        policyPath: String,
        mode: String,
        importedProjectCount: Int,
        finalProjectCount: Int,
        policy: ProjectDependencyPolicy,
        nonClaims: [String]
    ) {
        self.sourcePath = sourcePath
        self.policyPath = policyPath
        self.mode = mode
        self.importedProjectCount = importedProjectCount
        self.finalProjectCount = finalProjectCount
        self.policy = policy
        self.nonClaims = nonClaims
    }
}

public enum ProjectDependencyPolicyDocumentError: LocalizedError {
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported project dependency policy document schema version: \(version)"
        }
    }
}

public final class ProjectDependencyPolicyStore: @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL = ProjectDependencyPolicyStore.defaultRoot(), fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_CONFIG_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ryddi/Config", isDirectory: true)
    }

    public var policyURL: URL {
        root.appendingPathComponent("project-dependency-policy.json")
    }

    public func load() -> ProjectDependencyPolicy {
        guard let data = try? Data(contentsOf: policyURL),
              let policy = try? decoder.decode(ProjectDependencyPolicy.self, from: data) else {
            return .empty
        }
        return policy
    }

    public func exportDocument(exportedAt: Date = Date()) -> ProjectDependencyPolicyDocument {
        ProjectDependencyPolicyDocument(exportedAt: exportedAt, projects: load().projects)
    }

    @discardableResult
    public func writeExport(_ document: ProjectDependencyPolicyDocument, to url: URL) throws -> URL {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(document).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    public func importDocument(from url: URL, merge: Bool = true) throws -> ProjectDependencyPolicyImportResult {
        let data = try Data(contentsOf: url)
        let document = try decodePolicyDocument(from: data)
        guard document.schemaVersion == ProjectDependencyPolicyDocument.currentSchemaVersion else {
            throw ProjectDependencyPolicyDocumentError.unsupportedSchemaVersion(document.schemaVersion)
        }

        let imported = document.policy
        let finalPolicy: ProjectDependencyPolicy
        if merge {
            let importedPaths = Set(imported.projects.map(\.projectRootPath))
            let retained = load().projects.filter { !importedPaths.contains($0.projectRootPath) }
            finalPolicy = ProjectDependencyPolicy(projects: retained + imported.projects)
        } else {
            finalPolicy = imported
        }
        try save(finalPolicy)
        return ProjectDependencyPolicyImportResult(
            sourcePath: url.standardizedFileURL.path,
            policyPath: policyURL.path,
            mode: merge ? "merge" : "replace",
            importedProjectCount: imported.projects.count,
            finalProjectCount: finalPolicy.projects.count,
            policy: finalPolicy,
            nonClaims: document.nonClaims
        )
    }

    @discardableResult
    public func save(_ policy: ProjectDependencyPolicy) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(policy).write(to: policyURL, options: .atomic)
        return policyURL
    }

    @discardableResult
    public func set(
        projectRootPath: String,
        projectName: String? = nil,
        decision: ProjectDependencyPolicyDecision,
        reason: String? = nil,
        updatedAt: Date = Date()
    ) throws -> ProjectDependencyPolicy {
        let policy = load().setting(
            projectRootPath: projectRootPath,
            projectName: projectName,
            decision: decision,
            reason: reason,
            updatedAt: updatedAt
        )
        try save(policy)
        return policy
    }

    @discardableResult
    public func remove(projectRootPath: String) throws -> ProjectDependencyPolicy {
        let policy = load().removing(projectRootPath: projectRootPath)
        try save(policy)
        return policy
    }

    private func decodePolicyDocument(from data: Data) throws -> ProjectDependencyPolicyDocument {
        do {
            return try decoder.decode(ProjectDependencyPolicyDocument.self, from: data)
        } catch {
            let policy = try decoder.decode(ProjectDependencyPolicy.self, from: data)
            return ProjectDependencyPolicyDocument(projects: policy.projects)
        }
    }
}

private extension String {
    var standardizedFileURLPath: String {
        URL(fileURLWithPath: self).standardizedFileURL.path
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
