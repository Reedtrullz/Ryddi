import Foundation

public enum ProjectDependencyEcosystem: String, Codable, CaseIterable, Hashable, Sendable {
    case javascript
    case python
    case swift
    case rust
    case javaGradle
    case cocoaPods
    case dartFlutter
    case android
    case go
    case other

    public var label: String {
        switch self {
        case .javascript: return "JavaScript"
        case .python: return "Python"
        case .swift: return "Swift"
        case .rust: return "Rust"
        case .javaGradle: return "Java/Gradle"
        case .cocoaPods: return "CocoaPods"
        case .dartFlutter: return "Dart/Flutter"
        case .android: return "Android"
        case .go: return "Go"
        case .other: return "Other"
        }
    }

    public var nativeCleanupHint: String {
        switch self {
        case .javascript:
            return "Prefer package-manager reinstall/clean commands after reviewing lockfiles and active dev servers."
        case .python:
            return "Prefer recreating virtual environments from pyproject, requirements, Pipfile, or lockfiles."
        case .swift:
            return "Prefer `swift package clean` or Xcode cleanup after quitting active builds."
        case .rust:
            return "Prefer `cargo clean` after confirming build artifacts can be rebuilt."
        case .javaGradle:
            return "Prefer `./gradlew clean` and avoid removing Gradle config or active daemon state."
        case .cocoaPods:
            return "Prefer `pod install`/`pod deintegrate` workflows after reviewing local pod edits."
        case .dartFlutter:
            return "Prefer `flutter clean`/`dart pub get` after reviewing generated project state."
        case .android:
            return "Prefer Android Studio or Gradle cleanup after reviewing emulator/build state."
        case .go:
            return "Prefer Go tool cleanup for caches and rebuild project-local outputs deliberately."
        case .other:
            return "Prefer the owning tool's cleanup or rebuild command."
        }
    }
}

public enum ProjectDependencyKind: String, Codable, CaseIterable, Hashable, Sendable {
    case nodeModules
    case pythonVirtualEnvironment
    case swiftBuild
    case rustTarget
    case gradleProjectCache
    case gradleBuildOutput
    case webBuildOutput
    case webFrameworkCache
    case cocoaPodsPods
    case dartTool
    case androidBuild
    case goBuildOutput
    case coverageOutput
    case other

    public var label: String {
        switch self {
        case .nodeModules: return "node_modules"
        case .pythonVirtualEnvironment: return "Python virtualenv"
        case .swiftBuild: return "Swift .build"
        case .rustTarget: return "Rust target"
        case .gradleProjectCache: return "Gradle project cache"
        case .gradleBuildOutput: return "Gradle build output"
        case .webBuildOutput: return "Web build output"
        case .webFrameworkCache: return "Web framework cache"
        case .cocoaPodsPods: return "Pods"
        case .dartTool: return ".dart_tool"
        case .androidBuild: return "Android build output"
        case .goBuildOutput: return "Go build output"
        case .coverageOutput: return "Coverage output"
        case .other: return "Other project dependency"
        }
    }

    public var isRebuildable: Bool {
        switch self {
        case .nodeModules,
             .pythonVirtualEnvironment,
             .swiftBuild,
             .rustTarget,
             .gradleProjectCache,
             .gradleBuildOutput,
             .webBuildOutput,
             .webFrameworkCache,
             .dartTool,
             .androidBuild,
             .goBuildOutput,
             .coverageOutput:
            return true
        case .cocoaPodsPods, .other:
            return false
        }
    }
}

public enum ProjectDependencyVCSState: String, Codable, CaseIterable, Hashable, Sendable {
    case clean
    case dirty
    case untrackedOnly
    case notRepository
    case notChecked
    case checkFailed

    public var label: String {
        switch self {
        case .clean: return "Clean"
        case .dirty: return "Tracked changes"
        case .untrackedOnly: return "Untracked only"
        case .notRepository: return "No Git repository"
        case .notChecked: return "Not checked"
        case .checkFailed: return "Check failed"
        }
    }
}

public struct ProjectDependencyVCSInfo: Codable, Hashable, Sendable {
    public let system: String
    public let state: ProjectDependencyVCSState
    public let summary: String
    public let changedTrackedCount: Int
    public let untrackedCount: Int
    public let command: String?
    public let exitCode: Int32?

    public init(
        system: String,
        state: ProjectDependencyVCSState,
        summary: String,
        changedTrackedCount: Int = 0,
        untrackedCount: Int = 0,
        command: String? = nil,
        exitCode: Int32? = nil
    ) {
        self.system = system
        self.state = state
        self.summary = summary
        self.changedTrackedCount = max(0, changedTrackedCount)
        self.untrackedCount = max(0, untrackedCount)
        self.command = command
        self.exitCode = exitCode
    }

    public static let notChecked = ProjectDependencyVCSInfo(
        system: "git",
        state: .notChecked,
        summary: "Git status was not checked for this report.",
        command: "git status --porcelain=v1 --untracked-files=normal"
    )
}

public struct ProjectDependencyToolingInfo: Codable, Hashable, Sendable {
    public let toolName: String?
    public let toolVersion: String?
    public let toolSource: String?
    public let packageScripts: [String]
    public let notes: [String]

    public init(
        toolName: String? = nil,
        toolVersion: String? = nil,
        toolSource: String? = nil,
        packageScripts: [String] = [],
        notes: [String] = []
    ) {
        self.toolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.toolVersion = toolVersion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.toolSource = toolSource?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.packageScripts = Array(Set(packageScripts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.compactMap(\.nilIfEmpty))).sorted().prefixArray(50)
        self.notes = Array(Set(notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.compactMap(\.nilIfEmpty))).sorted().prefixArray(20)
    }

    public static let none = ProjectDependencyToolingInfo()

    public var toolLabel: String {
        guard let toolName else { return "Unknown tool" }
        if let toolVersion {
            return "\(toolName) \(toolVersion)"
        }
        return toolName
    }
}

public enum ProjectDependencyWorkspaceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case javascript
    case pnpm
    case yarn
    case npm
    case bun
    case turbo
    case nx
    case lerna
    case rush
    case cargo
    case gradle
    case other

    public var label: String {
        switch self {
        case .javascript: return "JavaScript workspace"
        case .pnpm: return "pnpm workspace"
        case .yarn: return "Yarn workspace"
        case .npm: return "npm workspace"
        case .bun: return "Bun workspace"
        case .turbo: return "Turborepo"
        case .nx: return "Nx workspace"
        case .lerna: return "Lerna workspace"
        case .rush: return "Rush workspace"
        case .cargo: return "Cargo workspace"
        case .gradle: return "Gradle multi-project"
        case .other: return "Workspace"
        }
    }
}

public struct ProjectDependencyWorkspaceInfo: Codable, Hashable, Sendable {
    public let rootPath: String?
    public let rootName: String?
    public let kind: ProjectDependencyWorkspaceKind?
    public let manifestHints: [String]
    public let packagePatterns: [String]
    public let evidence: [String]
    public let toolingInfo: ProjectDependencyToolingInfo

    public init(
        rootPath: String? = nil,
        rootName: String? = nil,
        kind: ProjectDependencyWorkspaceKind? = nil,
        manifestHints: [String] = [],
        packagePatterns: [String] = [],
        evidence: [String] = [],
        toolingInfo: ProjectDependencyToolingInfo = .none
    ) {
        self.rootPath = rootPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.rootName = rootName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.kind = kind
        self.manifestHints = Array(Set(manifestHints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.compactMap(\.nilIfEmpty))).sorted().prefixArray(50)
        self.packagePatterns = Array(Set(packagePatterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.compactMap(\.nilIfEmpty))).sorted().prefixArray(50)
        self.evidence = Array(Set(evidence.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.compactMap(\.nilIfEmpty))).sorted().prefixArray(20)
        self.toolingInfo = toolingInfo
    }

    public static let none = ProjectDependencyWorkspaceInfo()

    public var isWorkspace: Bool {
        rootPath != nil
    }

    public var label: String {
        let kindLabel = kind?.label ?? ProjectDependencyWorkspaceKind.other.label
        guard let rootName else { return kindLabel }
        return "\(rootName) (\(kindLabel))"
    }
}

public struct ProjectDependencyItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let displayName: String
    public let projectRootPath: String
    public let projectName: String
    public let ecosystem: ProjectDependencyEcosystem
    public let kind: ProjectDependencyKind
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let modificationDate: Date?
    public let ageDays: Int?
    public let manifestHints: [String]
    public let toolingInfo: ProjectDependencyToolingInfo
    public let workspaceInfo: ProjectDependencyWorkspaceInfo
    public let signals: [String]
    public let vcsInfo: ProjectDependencyVCSInfo
    public let commandHints: [NativeToolCommand]
    public let projectPolicyDecision: ProjectDependencyPolicyDecision?
    public let projectPolicyReason: String?
    public let recommendation: String
    public let guidance: [String]

    public init(
        id: String = UUID().uuidString,
        path: String,
        displayName: String,
        projectRootPath: String,
        projectName: String,
        ecosystem: ProjectDependencyEcosystem,
        kind: ProjectDependencyKind,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        modificationDate: Date? = nil,
        ageDays: Int? = nil,
        manifestHints: [String],
        toolingInfo: ProjectDependencyToolingInfo = .none,
        workspaceInfo: ProjectDependencyWorkspaceInfo = .none,
        signals: [String],
        vcsInfo: ProjectDependencyVCSInfo = .notChecked,
        commandHints: [NativeToolCommand] = [],
        projectPolicyDecision: ProjectDependencyPolicyDecision? = nil,
        projectPolicyReason: String? = nil,
        recommendation: String,
        guidance: [String]
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.projectRootPath = projectRootPath
        self.projectName = projectName
        self.ecosystem = ecosystem
        self.kind = kind
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.modificationDate = modificationDate
        self.ageDays = ageDays
        self.manifestHints = manifestHints
        self.toolingInfo = toolingInfo
        self.workspaceInfo = workspaceInfo
        self.signals = signals
        self.vcsInfo = vcsInfo
        self.commandHints = commandHints
        self.projectPolicyDecision = projectPolicyDecision
        self.projectPolicyReason = projectPolicyReason
        self.recommendation = recommendation
        self.guidance = guidance
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case displayName
        case projectRootPath
        case projectName
        case ecosystem
        case kind
        case logicalSize
        case allocatedSize
        case itemCount
        case isDirectory
        case isSymbolicLink
        case modificationDate
        case ageDays
        case manifestHints
        case toolingInfo
        case workspaceInfo
        case signals
        case vcsInfo
        case commandHints
        case projectPolicyDecision
        case projectPolicyReason
        case recommendation
        case guidance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        displayName = try container.decode(String.self, forKey: .displayName)
        projectRootPath = try container.decode(String.self, forKey: .projectRootPath)
        projectName = try container.decode(String.self, forKey: .projectName)
        ecosystem = try container.decode(ProjectDependencyEcosystem.self, forKey: .ecosystem)
        kind = try container.decode(ProjectDependencyKind.self, forKey: .kind)
        logicalSize = try container.decode(Int64.self, forKey: .logicalSize)
        allocatedSize = try container.decode(Int64.self, forKey: .allocatedSize)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        isSymbolicLink = try container.decode(Bool.self, forKey: .isSymbolicLink)
        modificationDate = try container.decodeIfPresent(Date.self, forKey: .modificationDate)
        ageDays = try container.decodeIfPresent(Int.self, forKey: .ageDays)
        manifestHints = try container.decode([String].self, forKey: .manifestHints)
        toolingInfo = try container.decodeIfPresent(ProjectDependencyToolingInfo.self, forKey: .toolingInfo) ?? .none
        workspaceInfo = try container.decodeIfPresent(ProjectDependencyWorkspaceInfo.self, forKey: .workspaceInfo) ?? .none
        signals = try container.decode([String].self, forKey: .signals)
        vcsInfo = try container.decodeIfPresent(ProjectDependencyVCSInfo.self, forKey: .vcsInfo) ?? .notChecked
        commandHints = try container.decodeIfPresent([NativeToolCommand].self, forKey: .commandHints) ?? []
        projectPolicyDecision = try container.decodeIfPresent(ProjectDependencyPolicyDecision.self, forKey: .projectPolicyDecision)
        projectPolicyReason = try container.decodeIfPresent(String.self, forKey: .projectPolicyReason)
        recommendation = try container.decode(String.self, forKey: .recommendation)
        guidance = try container.decode([String].self, forKey: .guidance)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(projectRootPath, forKey: .projectRootPath)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(ecosystem, forKey: .ecosystem)
        try container.encode(kind, forKey: .kind)
        try container.encode(logicalSize, forKey: .logicalSize)
        try container.encode(allocatedSize, forKey: .allocatedSize)
        try container.encode(itemCount, forKey: .itemCount)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(isSymbolicLink, forKey: .isSymbolicLink)
        try container.encodeIfPresent(modificationDate, forKey: .modificationDate)
        try container.encodeIfPresent(ageDays, forKey: .ageDays)
        try container.encode(manifestHints, forKey: .manifestHints)
        try container.encode(toolingInfo, forKey: .toolingInfo)
        try container.encode(workspaceInfo, forKey: .workspaceInfo)
        try container.encode(signals, forKey: .signals)
        try container.encode(vcsInfo, forKey: .vcsInfo)
        try container.encode(commandHints, forKey: .commandHints)
        try container.encodeIfPresent(projectPolicyDecision, forKey: .projectPolicyDecision)
        try container.encodeIfPresent(projectPolicyReason, forKey: .projectPolicyReason)
        try container.encode(recommendation, forKey: .recommendation)
        try container.encode(guidance, forKey: .guidance)
    }
}

public struct ProjectDependencyRootSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let rootPath: String
    public let permissionState: PermissionState
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let candidateCount: Int
    public let note: String

    public init(
        id: String = UUID().uuidString,
        rootPath: String,
        permissionState: PermissionState,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        candidateCount: Int,
        note: String
    ) {
        self.id = id
        self.rootPath = rootPath
        self.permissionState = permissionState
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.candidateCount = candidateCount
        self.note = note
    }
}

public struct ProjectDependencyProtectedProjectRoot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let projectRootPath: String
    public let projectName: String
    public let manifestHints: [String]
    public let toolingInfo: ProjectDependencyToolingInfo
    public let workspaceInfo: ProjectDependencyWorkspaceInfo
    public let vcsInfo: ProjectDependencyVCSInfo
    public let projectPolicyDecision: ProjectDependencyPolicyDecision?
    public let projectPolicyReason: String?
    public let note: String

    public init(
        id: String = UUID().uuidString,
        projectRootPath: String,
        projectName: String,
        manifestHints: [String],
        toolingInfo: ProjectDependencyToolingInfo = .none,
        workspaceInfo: ProjectDependencyWorkspaceInfo = .none,
        vcsInfo: ProjectDependencyVCSInfo = .notChecked,
        projectPolicyDecision: ProjectDependencyPolicyDecision? = nil,
        projectPolicyReason: String? = nil,
        note: String
    ) {
        self.id = id
        self.projectRootPath = projectRootPath
        self.projectName = projectName
        self.manifestHints = manifestHints
        self.toolingInfo = toolingInfo
        self.workspaceInfo = workspaceInfo
        self.vcsInfo = vcsInfo
        self.projectPolicyDecision = projectPolicyDecision
        self.projectPolicyReason = projectPolicyReason
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectRootPath
        case projectName
        case manifestHints
        case toolingInfo
        case workspaceInfo
        case vcsInfo
        case projectPolicyDecision
        case projectPolicyReason
        case note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectRootPath = try container.decode(String.self, forKey: .projectRootPath)
        projectName = try container.decode(String.self, forKey: .projectName)
        manifestHints = try container.decode([String].self, forKey: .manifestHints)
        toolingInfo = try container.decodeIfPresent(ProjectDependencyToolingInfo.self, forKey: .toolingInfo) ?? .none
        workspaceInfo = try container.decodeIfPresent(ProjectDependencyWorkspaceInfo.self, forKey: .workspaceInfo) ?? .none
        vcsInfo = try container.decodeIfPresent(ProjectDependencyVCSInfo.self, forKey: .vcsInfo) ?? .notChecked
        projectPolicyDecision = try container.decodeIfPresent(ProjectDependencyPolicyDecision.self, forKey: .projectPolicyDecision)
        projectPolicyReason = try container.decodeIfPresent(String.self, forKey: .projectPolicyReason)
        note = try container.decode(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectRootPath, forKey: .projectRootPath)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(manifestHints, forKey: .manifestHints)
        try container.encode(toolingInfo, forKey: .toolingInfo)
        try container.encode(workspaceInfo, forKey: .workspaceInfo)
        try container.encode(vcsInfo, forKey: .vcsInfo)
        try container.encodeIfPresent(projectPolicyDecision, forKey: .projectPolicyDecision)
        try container.encodeIfPresent(projectPolicyReason, forKey: .projectPolicyReason)
        try container.encode(note, forKey: .note)
    }
}

public struct ProjectDependencyPolicySkippedProject: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let projectRootPath: String
    public let projectName: String
    public let manifestHints: [String]
    public let workspaceInfo: ProjectDependencyWorkspaceInfo?
    public let decision: ProjectDependencyPolicyDecision
    public let reason: String?
    public let note: String

    public init(
        id: String = UUID().uuidString,
        projectRootPath: String,
        projectName: String,
        manifestHints: [String],
        workspaceInfo: ProjectDependencyWorkspaceInfo? = nil,
        decision: ProjectDependencyPolicyDecision,
        reason: String? = nil,
        note: String
    ) {
        self.id = id
        self.projectRootPath = projectRootPath
        self.projectName = projectName
        self.manifestHints = manifestHints
        self.workspaceInfo = workspaceInfo
        self.decision = decision
        self.reason = reason
        self.note = note
    }
}

public struct ProjectDependencySummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let itemCount: Int
    public let allocatedSize: Int64

    public init(name: String, itemCount: Int, allocatedSize: Int64) {
        self.name = name
        self.itemCount = itemCount
        self.allocatedSize = allocatedSize
    }
}

public struct ProjectDependencyReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let itemCount: Int
    public let displayedItemCount: Int
    public let candidateBytes: Int64
    public let rebuildableBytes: Int64
    public let reviewRequiredBytes: Int64
    public let rootSummaries: [ProjectDependencyRootSummary]
    public let ecosystemSummaries: [ProjectDependencySummary]
    public let kindSummaries: [ProjectDependencySummary]
    public let toolSummaries: [ProjectDependencySummary]
    public let scriptSummaries: [ProjectDependencySummary]
    public let workspaceSummaries: [ProjectDependencySummary]
    public let vcsSummaries: [ProjectDependencySummary]
    public let policySummaries: [ProjectDependencySummary]
    public let workspaceRootCount: Int
    public let projectsWithDirtyVCSCount: Int
    public let largestItems: [ProjectDependencyItem]
    public let protectedProjectRoots: [ProjectDependencyProtectedProjectRoot]
    public let policySkippedProjects: [ProjectDependencyPolicySkippedProject]
    public let guidance: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        itemCount: Int,
        displayedItemCount: Int,
        candidateBytes: Int64,
        rebuildableBytes: Int64,
        reviewRequiredBytes: Int64,
        rootSummaries: [ProjectDependencyRootSummary],
        ecosystemSummaries: [ProjectDependencySummary],
        kindSummaries: [ProjectDependencySummary],
        toolSummaries: [ProjectDependencySummary] = [],
        scriptSummaries: [ProjectDependencySummary] = [],
        workspaceSummaries: [ProjectDependencySummary] = [],
        vcsSummaries: [ProjectDependencySummary] = [],
        policySummaries: [ProjectDependencySummary] = [],
        workspaceRootCount: Int = 0,
        projectsWithDirtyVCSCount: Int = 0,
        largestItems: [ProjectDependencyItem],
        protectedProjectRoots: [ProjectDependencyProtectedProjectRoot],
        policySkippedProjects: [ProjectDependencyPolicySkippedProject] = [],
        guidance: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.itemCount = itemCount
        self.displayedItemCount = displayedItemCount
        self.candidateBytes = candidateBytes
        self.rebuildableBytes = rebuildableBytes
        self.reviewRequiredBytes = reviewRequiredBytes
        self.rootSummaries = rootSummaries
        self.ecosystemSummaries = ecosystemSummaries
        self.kindSummaries = kindSummaries
        self.toolSummaries = toolSummaries
        self.scriptSummaries = scriptSummaries
        self.workspaceSummaries = workspaceSummaries
        self.vcsSummaries = vcsSummaries
        self.policySummaries = policySummaries
        self.workspaceRootCount = max(0, workspaceRootCount)
        self.projectsWithDirtyVCSCount = max(0, projectsWithDirtyVCSCount)
        self.largestItems = largestItems
        self.protectedProjectRoots = protectedProjectRoots
        self.policySkippedProjects = policySkippedProjects
        self.guidance = guidance
        self.nonClaims = nonClaims
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case totalLogicalSize
        case totalAllocatedSize
        case itemCount
        case displayedItemCount
        case candidateBytes
        case rebuildableBytes
        case reviewRequiredBytes
        case rootSummaries
        case ecosystemSummaries
        case kindSummaries
        case toolSummaries
        case scriptSummaries
        case workspaceSummaries
        case vcsSummaries
        case policySummaries
        case workspaceRootCount
        case projectsWithDirtyVCSCount
        case largestItems
        case protectedProjectRoots
        case policySkippedProjects
        case guidance
        case nonClaims
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        totalLogicalSize = try container.decode(Int64.self, forKey: .totalLogicalSize)
        totalAllocatedSize = try container.decode(Int64.self, forKey: .totalAllocatedSize)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        displayedItemCount = try container.decode(Int.self, forKey: .displayedItemCount)
        candidateBytes = try container.decode(Int64.self, forKey: .candidateBytes)
        rebuildableBytes = try container.decode(Int64.self, forKey: .rebuildableBytes)
        reviewRequiredBytes = try container.decode(Int64.self, forKey: .reviewRequiredBytes)
        rootSummaries = try container.decode([ProjectDependencyRootSummary].self, forKey: .rootSummaries)
        ecosystemSummaries = try container.decode([ProjectDependencySummary].self, forKey: .ecosystemSummaries)
        kindSummaries = try container.decode([ProjectDependencySummary].self, forKey: .kindSummaries)
        toolSummaries = try container.decodeIfPresent([ProjectDependencySummary].self, forKey: .toolSummaries) ?? []
        scriptSummaries = try container.decodeIfPresent([ProjectDependencySummary].self, forKey: .scriptSummaries) ?? []
        workspaceSummaries = try container.decodeIfPresent([ProjectDependencySummary].self, forKey: .workspaceSummaries) ?? []
        vcsSummaries = try container.decodeIfPresent([ProjectDependencySummary].self, forKey: .vcsSummaries) ?? []
        policySummaries = try container.decodeIfPresent([ProjectDependencySummary].self, forKey: .policySummaries) ?? []
        workspaceRootCount = try container.decodeIfPresent(Int.self, forKey: .workspaceRootCount) ?? 0
        projectsWithDirtyVCSCount = try container.decodeIfPresent(Int.self, forKey: .projectsWithDirtyVCSCount) ?? 0
        largestItems = try container.decode([ProjectDependencyItem].self, forKey: .largestItems)
        protectedProjectRoots = try container.decode([ProjectDependencyProtectedProjectRoot].self, forKey: .protectedProjectRoots)
        policySkippedProjects = try container.decodeIfPresent([ProjectDependencyPolicySkippedProject].self, forKey: .policySkippedProjects) ?? []
        guidance = try container.decode([String].self, forKey: .guidance)
        nonClaims = try container.decode([String].self, forKey: .nonClaims)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(totalLogicalSize, forKey: .totalLogicalSize)
        try container.encode(totalAllocatedSize, forKey: .totalAllocatedSize)
        try container.encode(itemCount, forKey: .itemCount)
        try container.encode(displayedItemCount, forKey: .displayedItemCount)
        try container.encode(candidateBytes, forKey: .candidateBytes)
        try container.encode(rebuildableBytes, forKey: .rebuildableBytes)
        try container.encode(reviewRequiredBytes, forKey: .reviewRequiredBytes)
        try container.encode(rootSummaries, forKey: .rootSummaries)
        try container.encode(ecosystemSummaries, forKey: .ecosystemSummaries)
        try container.encode(kindSummaries, forKey: .kindSummaries)
        try container.encode(toolSummaries, forKey: .toolSummaries)
        try container.encode(scriptSummaries, forKey: .scriptSummaries)
        try container.encode(workspaceSummaries, forKey: .workspaceSummaries)
        try container.encode(vcsSummaries, forKey: .vcsSummaries)
        try container.encode(policySummaries, forKey: .policySummaries)
        try container.encode(workspaceRootCount, forKey: .workspaceRootCount)
        try container.encode(projectsWithDirtyVCSCount, forKey: .projectsWithDirtyVCSCount)
        try container.encode(largestItems, forKey: .largestItems)
        try container.encode(protectedProjectRoots, forKey: .protectedProjectRoots)
        try container.encode(policySkippedProjects, forKey: .policySkippedProjects)
        try container.encode(guidance, forKey: .guidance)
        try container.encode(nonClaims, forKey: .nonClaims)
    }
}

public struct ProjectDependencyReviewOptions: Hashable, Sendable {
    public let roots: [URL]
    public let limit: Int
    public let oldDays: Int
    public let maximumSearchDepth: Int
    public let measurementDepth: Int
    public let includeMissingRoots: Bool
    public let includeVCSStatus: Bool
    public let projectPolicy: ProjectDependencyPolicy
    public let includePolicySkippedProjects: Bool

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: [URL]? = nil,
        limit: Int = 50,
        oldDays: Int = 90,
        maximumSearchDepth: Int = 6,
        measurementDepth: Int = 8,
        includeMissingRoots: Bool = true,
        includeVCSStatus: Bool = false,
        projectPolicy: ProjectDependencyPolicy = .empty,
        includePolicySkippedProjects: Bool = false
    ) {
        let standardizedHome = home.standardizedFileURL
        self.roots = (roots ?? Self.defaultRoots(home: standardizedHome)).map { $0.standardizedFileURL }
        self.limit = max(1, min(limit, 500))
        self.oldDays = max(1, min(oldDays, 3650))
        self.maximumSearchDepth = max(0, min(maximumSearchDepth, 24))
        self.measurementDepth = max(0, min(measurementDepth, 32))
        self.includeMissingRoots = includeMissingRoots
        self.includeVCSStatus = includeVCSStatus
        self.projectPolicy = projectPolicy
        self.includePolicySkippedProjects = includePolicySkippedProjects
    }

    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Projectos"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Documents/GitHub"),
            home.appendingPathComponent("Documents/Projects"),
            home.appendingPathComponent("Work")
        ]
    }
}

public final class ProjectDependencyReviewScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func review(
        options: ProjectDependencyReviewOptions = ProjectDependencyReviewOptions(),
        createdAt: Date = Date()
    ) -> ProjectDependencyReviewReport {
        var summaries: [ProjectDependencyRootSummary] = []
        var items: [ProjectDependencyItem] = []
        var skippedProjects: [ProjectDependencyPolicySkippedProject] = []

        for root in options.roots {
            let result = inspect(
                root: root,
                oldDays: options.oldDays,
                maximumSearchDepth: options.maximumSearchDepth,
                measurementDepth: options.measurementDepth,
                includeVCSStatus: options.includeVCSStatus,
                projectPolicy: options.projectPolicy,
                includePolicySkippedProjects: options.includePolicySkippedProjects,
                referenceDate: createdAt
            )
            if result.summary.permissionState != .missing || options.includeMissingRoots {
                summaries.append(result.summary)
            }
            items.append(contentsOf: result.items)
            skippedProjects.append(contentsOf: result.skippedProjects)
        }

        let sortedSkippedProjects = Self.deduplicatedSkippedProjects(skippedProjects)
        let sortedItems = items.sorted { lhs, rhs in
            if lhs.allocatedSize == rhs.allocatedSize {
                return lhs.path < rhs.path
            }
            return lhs.allocatedSize > rhs.allocatedSize
        }
        let logical = sortedItems.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = sortedItems.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let measuredCount = sortedItems.reduce(0) { $0 + max(1, $1.itemCount) }
        let rebuildable = sortedItems
            .filter { $0.kind.isRebuildable }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let reviewRequired = sortedItems
            .filter { !$0.kind.isRebuildable }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }

        return ProjectDependencyReviewReport(
            createdAt: createdAt,
            totalLogicalSize: logical,
            totalAllocatedSize: allocated,
            itemCount: measuredCount,
            displayedItemCount: min(sortedItems.count, options.limit),
            candidateBytes: allocated,
            rebuildableBytes: rebuildable,
            reviewRequiredBytes: reviewRequired,
            rootSummaries: summaries,
            ecosystemSummaries: Self.ecosystemSummaries(for: sortedItems),
            kindSummaries: Self.kindSummaries(for: sortedItems),
            toolSummaries: Self.toolSummaries(for: sortedItems),
            scriptSummaries: Self.scriptSummaries(for: sortedItems),
            workspaceSummaries: Self.workspaceSummaries(for: sortedItems),
            vcsSummaries: Self.vcsSummaries(for: sortedItems),
            policySummaries: Self.policySummaries(for: sortedItems),
            workspaceRootCount: Self.workspaceRootCount(for: sortedItems),
            projectsWithDirtyVCSCount: Self.projectsWithDirtyVCSCount(for: sortedItems),
            largestItems: Array(sortedItems.prefix(options.limit)),
            protectedProjectRoots: protectedProjectRoots(for: sortedItems),
            policySkippedProjects: sortedSkippedProjects,
            guidance: Self.guidance,
            nonClaims: Self.nonClaims
        )
    }

    private func inspect(
        root: URL,
        oldDays: Int,
        maximumSearchDepth: Int,
        measurementDepth: Int,
        includeVCSStatus: Bool,
        projectPolicy: ProjectDependencyPolicy,
        includePolicySkippedProjects: Bool,
        referenceDate: Date
    ) -> (summary: ProjectDependencyRootSummary, items: [ProjectDependencyItem], skippedProjects: [ProjectDependencyPolicySkippedProject]) {
        let root = root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return (
                ProjectDependencyRootSummary(
                    rootPath: root.path,
                    permissionState: .missing,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    candidateCount: 0,
                    note: "Project dependency review root does not exist at \(root.path)."
                ),
                [],
                []
            )
        }
        guard isDirectory.boolValue else {
            return (
                ProjectDependencyRootSummary(
                    rootPath: root.path,
                    permissionState: .unknown,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    candidateCount: 0,
                    note: "Configured project dependency review root is not a directory: \(root.path)."
                ),
                [],
                []
            )
        }
        guard fileManager.isReadableFile(atPath: root.path) else {
            return (
                ProjectDependencyRootSummary(
                    rootPath: root.path,
                    permissionState: .denied,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    candidateCount: 0,
                    note: "Project dependency review root is not readable with current permissions: \(root.path)."
                ),
                [],
                []
            )
        }

        var vcsCache: [String: ProjectDependencyVCSInfo] = [:]
        let result = projectDependencyItems(
            under: root,
            oldDays: oldDays,
            maximumSearchDepth: maximumSearchDepth,
            measurementDepth: measurementDepth,
            includeVCSStatus: includeVCSStatus,
            projectPolicy: projectPolicy,
            includePolicySkippedProjects: includePolicySkippedProjects,
            vcsCache: &vcsCache,
            referenceDate: referenceDate
        )
        let items = result.items
        let logical = items.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = items.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let count = items.reduce(0) { $0 + max(1, $1.itemCount) }
        return (
            ProjectDependencyRootSummary(
                rootPath: root.path,
                permissionState: .readable,
                logicalSize: logical,
                allocatedSize: allocated,
                itemCount: count,
                candidateCount: items.count,
                note: result.skippedProjects.isEmpty
                    ? "Measured recognized project-local dependency and build artifact directories under \(root.path)."
                    : "Measured recognized project-local dependency and build artifact directories under \(root.path). Skipped \(result.skippedProjects.count) project(s) by saved Project Dependencies policy."
            ),
            items,
            result.skippedProjects
        )
    }

    private func projectDependencyItems(
        under root: URL,
        oldDays: Int,
        maximumSearchDepth: Int,
        measurementDepth: Int,
        includeVCSStatus: Bool,
        projectPolicy: ProjectDependencyPolicy,
        includePolicySkippedProjects: Bool,
        vcsCache: inout [String: ProjectDependencyVCSInfo],
        referenceDate: Date
    ) -> (items: [ProjectDependencyItem], skippedProjects: [ProjectDependencyPolicySkippedProject]) {
        var items: [ProjectDependencyItem] = []
        var skippedProjects: [ProjectDependencyPolicySkippedProject] = []

        if let values = try? root.resourceValues(forKeys: Set(projectDependencyResourceKeys)),
           values.isSymbolicLink != true,
           values.isDirectory == true,
           let metadata = candidateMetadata(for: root, boundary: root.deletingLastPathComponent().standardizedFileURL) {
            let policyRule = projectPolicy.matchingPolicy(forProjectRoot: metadata.projectRoot.path)
            if shouldSkipByPolicy(policyRule, includePolicySkippedProjects: includePolicySkippedProjects) {
                skippedProjects.append(skippedProject(for: metadata, policyRule: policyRule))
                return (items, skippedProjects)
            }
            items.append(
                item(
                    for: root,
                    metadata: metadata,
                    values: values,
                    oldDays: oldDays,
                    measurementDepth: measurementDepth,
                    includeVCSStatus: includeVCSStatus,
                    policyRule: policyRule,
                    policySkipOverridden: policyRule?.decision == .skipReview,
                    vcsCache: &vcsCache,
                    referenceDate: referenceDate
                )
            )
            return (items, skippedProjects)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: projectDependencyResourceKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return (items, skippedProjects)
        }

        for case let child as URL in enumerator {
            let depth = max(0, child.pathComponents.count - root.pathComponents.count)
            if depth > maximumSearchDepth {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? child.resourceValues(forKeys: Set(projectDependencyResourceKeys)) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isDirectory == true else { continue }
            if Self.shouldSkipTraversal(name: child.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if let metadata = candidateMetadata(for: child, boundary: root) {
                let policyRule = projectPolicy.matchingPolicy(forProjectRoot: metadata.projectRoot.path)
                if shouldSkipByPolicy(policyRule, includePolicySkippedProjects: includePolicySkippedProjects) {
                    skippedProjects.append(skippedProject(for: metadata, policyRule: policyRule))
                    enumerator.skipDescendants()
                    continue
                }
                items.append(
                    item(
                        for: child,
                        metadata: metadata,
                        values: values,
                        oldDays: oldDays,
                        measurementDepth: measurementDepth,
                        includeVCSStatus: includeVCSStatus,
                        policyRule: policyRule,
                        policySkipOverridden: policyRule?.decision == .skipReview,
                        vcsCache: &vcsCache,
                        referenceDate: referenceDate
                    )
                )
                enumerator.skipDescendants()
            }
        }

        return (items, skippedProjects)
    }

    private func item(
        for url: URL,
        metadata: ProjectDependencyCandidateMetadata,
        values: URLResourceValues,
        oldDays: Int,
        measurementDepth: Int,
        includeVCSStatus: Bool,
        policyRule: ProjectDependencyProjectPolicy?,
        policySkipOverridden: Bool,
        vcsCache: inout [String: ProjectDependencyVCSInfo],
        referenceDate: Date
    ) -> ProjectDependencyItem {
        let measurement = measure(url: url, maxDepth: measurementDepth)
        let modified = values.contentModificationDate
        let ageDays = modified.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: referenceDate).day ?? 0) }
        let isOld = (ageDays ?? 0) >= oldDays
        var signals = ["project-dependency", metadata.ecosystem.rawValue, metadata.kind.rawValue]
        if metadata.kind.isRebuildable {
            signals.append("rebuildable-after-review")
        }
        if isOld {
            signals.append("old-project-artifact")
        }
        if values.isSymbolicLink == true {
            signals.append("symlink-not-followed")
        }
        if let policyRule {
            switch policyRule.decision {
            case .review:
                signals.append("project-policy-review")
            case .preserve:
                signals.append("project-policy-preserve")
            case .skipReview:
                signals.append(policySkipOverridden ? "project-policy-skip-overridden" : "project-policy-skip")
            }
        }
        let vcsInfo = vcsInfo(for: metadata.projectRoot, includeStatus: includeVCSStatus, cache: &vcsCache)
        let commandHints = Self.commandHints(for: metadata)
        if let toolName = metadata.toolingInfo.toolName {
            signals.append("tool-\(Self.signalToken(toolName))")
        }
        if !metadata.toolingInfo.packageScripts.isEmpty {
            signals.append("package-json-scripts")
        }
        if metadata.workspaceInfo.isWorkspace {
            signals.append("workspace-detected")
            if let kind = metadata.workspaceInfo.kind {
                signals.append("workspace-\(kind.rawValue)")
            }
        }
        for command in commandHints where command.id.contains(".script.") {
            signals.append("script-command-hint")
            break
        }
        switch vcsInfo.state {
        case .clean:
            signals.append("vcs-clean")
        case .dirty:
            signals.append("vcs-tracked-changes")
        case .untrackedOnly:
            signals.append("vcs-untracked-only")
        case .notRepository:
            signals.append("vcs-not-repository")
        case .notChecked:
            signals.append("vcs-not-checked")
        case .checkFailed:
            signals.append("vcs-check-failed")
        }

        return ProjectDependencyItem(
            path: url.path,
            displayName: url.lastPathComponent,
            projectRootPath: metadata.projectRoot.path,
            projectName: metadata.projectRoot.lastPathComponent,
            ecosystem: metadata.ecosystem,
            kind: metadata.kind,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            itemCount: measurement.itemCount,
            isDirectory: values.isDirectory ?? false,
            isSymbolicLink: values.isSymbolicLink ?? false,
            modificationDate: modified,
            ageDays: ageDays,
            manifestHints: metadata.manifestHints,
            toolingInfo: metadata.toolingInfo,
            workspaceInfo: metadata.workspaceInfo,
            signals: signals,
            vcsInfo: vcsInfo,
            commandHints: commandHints,
            projectPolicyDecision: policyRule?.decision,
            projectPolicyReason: policyRule?.reason,
            recommendation: Self.recommendation(for: metadata, isOld: isOld),
            guidance: Self.itemGuidance(
                for: metadata,
                isOld: isOld,
                isSymbolicLink: values.isSymbolicLink == true,
                policyRule: policyRule,
                policySkipOverridden: policySkipOverridden
            )
        )
    }

    private func candidateMetadata(for url: URL, boundary: URL) -> ProjectDependencyCandidateMetadata? {
        let name = url.lastPathComponent
        let lowerName = name.lowercased()
        let project = projectRoot(for: url, boundary: boundary)
        let workspaceInfo = workspaceInfo(for: project.root, boundary: boundary)
        let hints = project.manifestHints
        let hintSet = Set(hints)
        let toolingInfo = effectiveToolingInfo(project: project.toolingInfo, workspace: workspaceInfo)

        func metadata(_ ecosystem: ProjectDependencyEcosystem, _ kind: ProjectDependencyKind) -> ProjectDependencyCandidateMetadata {
            ProjectDependencyCandidateMetadata(projectRoot: project.root, manifestHints: hints, toolingInfo: toolingInfo, workspaceInfo: workspaceInfo, ecosystem: ecosystem, kind: kind)
        }

        if lowerName == "node_modules" {
            return metadata(.javascript, .nodeModules)
        }
        if lowerName == ".venv" || lowerName == "venv" || lowerName == ".tox" {
            if hasPythonVirtualEnvironmentEvidence(at: url) || hintSet.contains("pyproject.toml") || hintSet.contains("requirements.txt") || hintSet.contains("Pipfile") || hintSet.contains("setup.py") {
                return metadata(.python, .pythonVirtualEnvironment)
            }
            if lowerName == ".venv" || lowerName == ".tox" {
                return metadata(.python, .pythonVirtualEnvironment)
            }
        }
        if lowerName == ".build", hintSet.contains("Package.swift") {
            return metadata(.swift, .swiftBuild)
        }
        if lowerName == "target", hintSet.contains("Cargo.toml") {
            return metadata(.rust, .rustTarget)
        }
        if lowerName == ".gradle", Self.hasGradleHint(hintSet) {
            return metadata(.javaGradle, .gradleProjectCache)
        }
        if lowerName == "pods", hintSet.contains("Podfile") {
            return metadata(.cocoaPods, .cocoaPodsPods)
        }
        if lowerName == ".dart_tool", hintSet.contains("pubspec.yaml") {
            return metadata(.dartFlutter, .dartTool)
        }
        if Self.webFrameworkCacheNames.contains(lowerName), Self.hasJavaScriptHint(hintSet) {
            return metadata(.javascript, .webFrameworkCache)
        }
        if Self.webBuildOutputNames.contains(lowerName), Self.hasJavaScriptHint(hintSet) {
            return metadata(.javascript, .webBuildOutput)
        }
        if lowerName == "coverage", Self.hasJavaScriptHint(hintSet) {
            return metadata(.javascript, .coverageOutput)
        }
        if lowerName == "build" {
            if hintSet.contains("pubspec.yaml") {
                return metadata(.dartFlutter, .androidBuild)
            }
            if Self.hasAndroidHint(hintSet) {
                return metadata(.android, .androidBuild)
            }
            if Self.hasGradleHint(hintSet) {
                return metadata(.javaGradle, .gradleBuildOutput)
            }
            if hintSet.contains("go.mod") {
                return metadata(.go, .goBuildOutput)
            }
        }

        return nil
    }

    private func projectRoot(for candidate: URL, boundary: URL) -> (root: URL, manifestHints: [String], toolingInfo: ProjectDependencyToolingInfo) {
        let boundary = boundary.standardizedFileURL
        var current = candidate.deletingLastPathComponent().standardizedFileURL
        var fallback = current
        while true {
            let hints = manifestHints(at: current)
            if !hints.isEmpty {
                return (current, hints, toolingInfo(at: current, manifestHints: hints))
            }
            if current.path == boundary.path || current.path == "/" {
                break
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                break
            }
            if current.path.hasPrefix(boundary.path + "/") {
                fallback = current
            }
            current = parent
        }
        let hints = manifestHints(at: fallback)
        return (fallback, hints, toolingInfo(at: fallback, manifestHints: hints))
    }

    private func manifestHints(at url: URL) -> [String] {
        var hints: [String] = []
        for filename in Self.manifestFiles where fileManager.fileExists(atPath: url.appendingPathComponent(filename).path) {
            hints.append(filename)
        }
        for path in Self.nestedManifestPaths where fileManager.fileExists(atPath: url.appendingPathComponent(path).path) {
            hints.append(path)
        }
        return hints
    }

    private func toolingInfo(at url: URL, manifestHints: [String]) -> ProjectDependencyToolingInfo {
        let hints = Set(manifestHints)
        var toolName: String?
        var toolVersion: String?
        var toolSource: String?
        var scripts: [String] = []
        var notes: [String] = []

        if hints.contains("package.json") {
            let packageInfo = packageJSONTooling(at: url.appendingPathComponent("package.json"))
            if let packageToolName = packageInfo.toolName {
                toolName = packageToolName
                toolVersion = packageInfo.toolVersion
                toolSource = "package.json packageManager"
            }
            scripts = packageInfo.scripts
            notes.append(contentsOf: packageInfo.notes)
        }

        if toolName == nil, let fallback = Self.fallbackTool(for: hints) {
            toolName = fallback.name
            toolSource = fallback.source
        }

        return ProjectDependencyToolingInfo(
            toolName: toolName,
            toolVersion: toolVersion,
            toolSource: toolSource,
            packageScripts: scripts,
            notes: notes
        )
    }

    private func effectiveToolingInfo(
        project: ProjectDependencyToolingInfo,
        workspace: ProjectDependencyWorkspaceInfo
    ) -> ProjectDependencyToolingInfo {
        let canInheritWorkspaceTool = project.toolName == nil || project.toolSource == "package.json"
        guard canInheritWorkspaceTool, workspace.isWorkspace, let workspaceTool = workspace.toolingInfo.toolName else {
            return project
        }
        var notes = project.notes
        notes.append("Inherited package-manager evidence from workspace root: \(workspace.label).")
        return ProjectDependencyToolingInfo(
            toolName: workspaceTool,
            toolVersion: workspace.toolingInfo.toolVersion,
            toolSource: workspace.toolingInfo.toolSource.map { "workspace \($0)" } ?? "workspace root",
            packageScripts: project.packageScripts,
            notes: notes
        )
    }

    private func workspaceInfo(for projectRoot: URL, boundary: URL) -> ProjectDependencyWorkspaceInfo {
        let boundary = boundary.standardizedFileURL
        var current = projectRoot.standardizedFileURL
        while true {
            if let workspace = workspaceInfo(at: current) {
                return workspace
            }
            if current.path == boundary.path || current.path == "/" {
                break
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return .none
    }

    private func workspaceInfo(at url: URL) -> ProjectDependencyWorkspaceInfo? {
        var workspaceManifestHints: [String] = []
        var evidence: [String] = []
        var packagePatterns: [String] = []
        var kind: ProjectDependencyWorkspaceKind?

        let packageJSON = url.appendingPathComponent("package.json")
        if fileManager.fileExists(atPath: packageJSON.path) {
            workspaceManifestHints.append("package.json")
            let workspace = packageJSONWorkspace(at: packageJSON)
            if !workspace.patterns.isEmpty {
                packagePatterns.append(contentsOf: workspace.patterns)
                evidence.append(contentsOf: workspace.evidence)
                kind = workspace.kind
            }
        }

        let pnpmWorkspace = url.appendingPathComponent("pnpm-workspace.yaml")
        if fileManager.fileExists(atPath: pnpmWorkspace.path) {
            workspaceManifestHints.append("pnpm-workspace.yaml")
            packagePatterns.append(contentsOf: pnpmWorkspacePatterns(at: pnpmWorkspace))
            evidence.append("Detected pnpm-workspace.yaml.")
            kind = .pnpm
        }

        if fileManager.fileExists(atPath: url.appendingPathComponent("lerna.json").path) {
            workspaceManifestHints.append("lerna.json")
            evidence.append("Detected lerna.json.")
            kind = kind ?? .lerna
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent("turbo.json").path) {
            workspaceManifestHints.append("turbo.json")
            evidence.append("Detected turbo.json.")
            kind = kind ?? .turbo
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent("nx.json").path) {
            workspaceManifestHints.append("nx.json")
            evidence.append("Detected nx.json.")
            kind = kind ?? .nx
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent("rush.json").path) {
            workspaceManifestHints.append("rush.json")
            evidence.append("Detected rush.json.")
            kind = kind ?? .rush
        }

        let cargoManifest = url.appendingPathComponent("Cargo.toml")
        if fileManager.fileExists(atPath: cargoManifest.path), cargoManifestContainsWorkspace(at: cargoManifest) {
            workspaceManifestHints.append("Cargo.toml")
            evidence.append("Detected Cargo.toml [workspace].")
            kind = kind ?? .cargo
        }

        for filename in ["settings.gradle", "settings.gradle.kts"] {
            let settings = url.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: settings.path), gradleSettingsContainsSubprojects(at: settings) {
                workspaceManifestHints.append(filename)
                evidence.append("Detected Gradle settings with included subprojects.")
                kind = kind ?? .gradle
            }
        }

        guard kind != nil || !evidence.isEmpty else { return nil }
        let rootHints = manifestHints(at: url)
        let tooling = toolingInfo(at: url, manifestHints: rootHints)
        return ProjectDependencyWorkspaceInfo(
            rootPath: url.path,
            rootName: url.lastPathComponent,
            kind: kind ?? .other,
            manifestHints: Array(Set(rootHints + workspaceManifestHints)).sorted(),
            packagePatterns: packagePatterns,
            evidence: evidence,
            toolingInfo: tooling
        )
    }

    private func packageJSONTooling(at url: URL) -> (toolName: String?, toolVersion: String?, scripts: [String], notes: [String]) {
        var notes: [String] = []
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else {
            return (nil, nil, [], [])
        }
        if (values.fileSize ?? 0) > 512_000 {
            return (nil, nil, [], ["package.json was larger than 512 KB; script and package-manager parsing was skipped."])
        }
        guard let data = try? Data(contentsOf: url) else {
            return (nil, nil, [], ["package.json could not be read for script and package-manager evidence."])
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return (nil, nil, [], ["package.json could not be parsed for script and package-manager evidence."])
        }

        let packageManager = (json["packageManager"] as? String).flatMap(Self.parsePackageManagerField)
        if let packageManager {
            notes.append("Detected packageManager field: \(packageManager.name)\(packageManager.version.map { "@\($0)" } ?? "").")
        }

        let rawScripts = (json["scripts"] as? [String: Any]) ?? [:]
        var omittedUnsafeScriptName = false
        let scripts = rawScripts.compactMap { key, value -> String? in
            guard value is String else { return nil }
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard Self.isSafePackageScriptName(trimmed) else {
                omittedUnsafeScriptName = true
                return nil
            }
            return trimmed
        }.sorted()

        if !scripts.isEmpty {
            notes.append("Detected package.json scripts: \(scripts.prefix(12).joined(separator: ", ")).")
        } else if !rawScripts.isEmpty {
            notes.append("package.json scripts were present but no simple script names were accepted for command hints.")
        } else {
            notes.append("package.json has no scripts object.")
        }
        if omittedUnsafeScriptName {
            notes.append("Some package.json script names were omitted because they are not simple command names.")
        }

        return (packageManager?.name, packageManager?.version, scripts, notes)
    }

    private func packageJSONWorkspace(at url: URL) -> (patterns: [String], evidence: [String], kind: ProjectDependencyWorkspaceKind?) {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) <= 512_000 else {
            return ([], [], nil)
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return ([], [], nil)
        }
        let packageManager = (json["packageManager"] as? String).flatMap(Self.parsePackageManagerField)
        var patterns: [String] = []
        if let array = json["workspaces"] as? [Any] {
            patterns.append(contentsOf: Self.safeWorkspacePatterns(array))
        } else if let object = json["workspaces"] as? [String: Any],
                  let packages = object["packages"] as? [Any] {
            patterns.append(contentsOf: Self.safeWorkspacePatterns(packages))
        }
        guard !patterns.isEmpty else { return ([], [], nil) }
        let kind = packageManager.map { Self.workspaceKind(forPackageManager: $0.name) } ?? .javascript
        return (
            patterns,
            ["Detected package.json workspaces: \(patterns.prefix(12).joined(separator: ", "))."],
            kind
        )
    }

    private func pnpmWorkspacePatterns(at url: URL) -> [String] {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) <= 512_000 else {
            return []
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        var inPackages = false
        var patterns: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }
            if trimmed == "packages:" {
                inPackages = true
                continue
            }
            guard inPackages else { continue }
            if trimmed.hasPrefix("-") {
                let pattern = trimmed
                    .dropFirst()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if Self.isSafeWorkspacePattern(pattern) {
                    patterns.append(pattern)
                }
            } else if !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t") {
                break
            }
        }
        return Array(Set(patterns)).sorted().prefixArray(50)
    }

    private func cargoManifestContainsWorkspace(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) <= 512_000 else {
            return false
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return text.split(whereSeparator: \.isNewline).contains { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines) == "[workspace]"
        }
    }

    private func gradleSettingsContainsSubprojects(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) <= 512_000 else {
            return false
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return text.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("include ") || trimmed.hasPrefix("include(")
        }
    }

    private func hasPythonVirtualEnvironmentEvidence(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path)
            || fileManager.fileExists(atPath: url.appendingPathComponent("bin/python").path)
            || fileManager.fileExists(atPath: url.appendingPathComponent("Scripts/python.exe").path)
    }

    private func protectedProjectRoots(for items: [ProjectDependencyItem]) -> [ProjectDependencyProtectedProjectRoot] {
        var seen: Set<String> = []
        return items
            .sorted { lhs, rhs in
                if lhs.projectName == rhs.projectName {
                    return lhs.projectRootPath < rhs.projectRootPath
                }
                return lhs.projectName < rhs.projectName
            }
            .compactMap { item in
                guard seen.insert(item.projectRootPath).inserted else { return nil }
                let hints = item.manifestHints
                let manifestText = hints.isEmpty ? "No standard manifest was found for this project root." : "Detected manifests: \(hints.joined(separator: ", "))."
                return ProjectDependencyProtectedProjectRoot(
                    projectRootPath: item.projectRootPath,
                    projectName: item.projectName,
                    manifestHints: hints,
                    toolingInfo: item.toolingInfo,
                    workspaceInfo: item.workspaceInfo,
                    vcsInfo: item.vcsInfo,
                    projectPolicyDecision: item.projectPolicyDecision,
                    projectPolicyReason: item.projectPolicyReason,
                    note: "Protected project files, source, manifests, lockfiles, env files, IDE settings, credentials, workspace metadata, and unknown project state are intentionally not measured as cleanup candidates. \(manifestText)"
                )
            }
    }

    private func shouldSkipByPolicy(
        _ policyRule: ProjectDependencyProjectPolicy?,
        includePolicySkippedProjects: Bool
    ) -> Bool {
        policyRule?.decision == .skipReview && !includePolicySkippedProjects
    }

    private func skippedProject(
        for metadata: ProjectDependencyCandidateMetadata,
        policyRule: ProjectDependencyProjectPolicy?
    ) -> ProjectDependencyPolicySkippedProject {
        let reason = policyRule?.reason
        let reasonText = reason.map { " Reason: \($0)" } ?? ""
        return ProjectDependencyPolicySkippedProject(
            projectRootPath: metadata.projectRoot.path,
            projectName: metadata.projectRoot.lastPathComponent,
            manifestHints: metadata.manifestHints,
            workspaceInfo: metadata.workspaceInfo.isWorkspace ? metadata.workspaceInfo : nil,
            decision: policyRule?.decision ?? .skipReview,
            reason: reason,
            note: "Saved Project Dependencies policy skipped this project from dependency/build artifact review.\(reasonText)"
        )
    }

    private func vcsInfo(
        for projectRoot: URL,
        includeStatus: Bool,
        cache: inout [String: ProjectDependencyVCSInfo]
    ) -> ProjectDependencyVCSInfo {
        let root = projectRoot.standardizedFileURL
        let key = root.path
        if let cached = cache[key] {
            return cached
        }

        let command = "git -C \(root.path) status --porcelain=v1 --untracked-files=normal"
        let info: ProjectDependencyVCSInfo
        if !includeStatus {
            if hasGitMarker(atOrAbove: root) {
                info = ProjectDependencyVCSInfo(
                    system: "git",
                    state: .notChecked,
                    summary: "Git repository marker detected; run with VCS status enabled to inspect tracked and untracked changes.",
                    command: command
                )
            } else {
                info = ProjectDependencyVCSInfo(
                    system: "none",
                    state: .notRepository,
                    summary: "No Git repository marker was detected for this project root."
                )
            }
            cache[key] = info
            return info
        }

        let result = runGitStatus(at: root, command: command)
        if result.exitCode == 0 {
            let counts = Self.parseGitStatus(result.stdout)
            let state: ProjectDependencyVCSState
            let summary: String
            if counts.changedTracked == 0 && counts.untracked == 0 {
                state = .clean
                summary = "Git status is clean for this project root."
            } else if counts.changedTracked == 0 {
                state = .untrackedOnly
                summary = "Git status has \(counts.untracked) untracked item(s) and no tracked changes."
            } else {
                state = .dirty
                summary = "Git status has \(counts.changedTracked) tracked change(s) and \(counts.untracked) untracked item(s)."
            }
            info = ProjectDependencyVCSInfo(
                system: "git",
                state: state,
                summary: summary,
                changedTrackedCount: counts.changedTracked,
                untrackedCount: counts.untracked,
                command: command,
                exitCode: result.exitCode
            )
        } else if result.stderr.localizedCaseInsensitiveContains("not a git repository")
            || result.stderr.localizedCaseInsensitiveContains("not in a git directory") {
            info = ProjectDependencyVCSInfo(
                system: "none",
                state: .notRepository,
                summary: "No Git repository was detected by `git status` for this project root.",
                command: command,
                exitCode: result.exitCode
            )
        } else {
            let trimmedError = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            info = ProjectDependencyVCSInfo(
                system: "git",
                state: .checkFailed,
                summary: trimmedError.isEmpty ? "Git status check failed or timed out." : "Git status check failed: \(trimmedError)",
                command: command,
                exitCode: result.exitCode
            )
        }
        cache[key] = info
        return info
    }

    private func hasGitMarker(atOrAbove url: URL) -> Bool {
        var current = url.standardizedFileURL
        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return true
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path || current.path == "/" {
                return false
            }
            current = parent
        }
    }

    private func runGitStatus(at root: URL, command: String) -> ProjectDependencyGitStatusResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root.path, "status", "--porcelain=v1", "--untracked-files=normal"]
        process.standardOutput = stdout
        process.standardError = stderr

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return ProjectDependencyGitStatusResult(
                stdout: "",
                stderr: "Could not start \(command): \(error.localizedDescription)",
                exitCode: -1
            )
        }

        if semaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
            process.terminate()
            return ProjectDependencyGitStatusResult(
                stdout: "",
                stderr: "Timed out while running \(command).",
                exitCode: -1
            )
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProjectDependencyGitStatusResult(stdout: output, stderr: errorOutput, exitCode: process.terminationStatus)
    }

    private func measure(url: URL, maxDepth: Int) -> ProjectDependencyMeasurement {
        guard let values = try? url.resourceValues(forKeys: Set(projectDependencyResourceKeys)) else {
            return ProjectDependencyMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }
        if values.isSymbolicLink == true {
            return ProjectDependencyMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return ProjectDependencyMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1)
        }
        guard maxDepth > 0 else {
            return ProjectDependencyMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: projectDependencyResourceKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return ProjectDependencyMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        for case let child as URL in enumerator {
            let depth = max(0, child.pathComponents.count - url.pathComponents.count)
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(projectDependencyResourceKeys)) else { continue }
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
        return ProjectDependencyMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: count)
    }

    private static func ecosystemSummaries(for items: [ProjectDependencyItem]) -> [ProjectDependencySummary] {
        ProjectDependencyEcosystem.allCases.compactMap { ecosystem in
            let matches = items.filter { $0.ecosystem == ecosystem }
            guard !matches.isEmpty else { return nil }
            return ProjectDependencySummary(
                name: ecosystem.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func kindSummaries(for items: [ProjectDependencyItem]) -> [ProjectDependencySummary] {
        ProjectDependencyKind.allCases.compactMap { kind in
            let matches = items.filter { $0.kind == kind }
            guard !matches.isEmpty else { return nil }
            return ProjectDependencySummary(
                name: kind.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func toolSummaries(for items: [ProjectDependencyItem]) -> [ProjectDependencySummary] {
        let names = Set(items.compactMap { $0.toolingInfo.toolName })
        return names.sorted().map { name in
            let matches = items.filter { $0.toolingInfo.toolName == name }
            return ProjectDependencySummary(
                name: name,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func scriptSummaries(for items: [ProjectDependencyItem]) -> [ProjectDependencySummary] {
        let scripts = Set(items.flatMap(\.toolingInfo.packageScripts))
        return scripts.sorted().map { script in
            let matches = items.filter { $0.toolingInfo.packageScripts.contains(script) }
            return ProjectDependencySummary(
                name: script,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func workspaceSummaries(for items: [ProjectDependencyItem]) -> [ProjectDependencySummary] {
        let workspacePaths = Set(items.compactMap(\.workspaceInfo.rootPath))
        return workspacePaths.sorted().map { path in
            let matches = items.filter { $0.workspaceInfo.rootPath == path }
            let label = matches.first?.workspaceInfo.label ?? URL(fileURLWithPath: path).lastPathComponent
            return ProjectDependencySummary(
                name: label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func vcsSummaries(for items: [ProjectDependencyItem]) -> [ProjectDependencySummary] {
        ProjectDependencyVCSState.allCases.compactMap { state in
            let matches = items.filter { $0.vcsInfo.state == state }
            guard !matches.isEmpty else { return nil }
            return ProjectDependencySummary(
                name: state.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func policySummaries(for items: [ProjectDependencyItem]) -> [ProjectDependencySummary] {
        ProjectDependencyPolicyDecision.allCases.compactMap { decision in
            let matches = items.filter { $0.projectPolicyDecision == decision }
            guard !matches.isEmpty else { return nil }
            return ProjectDependencySummary(
                name: decision.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func projectsWithDirtyVCSCount(for items: [ProjectDependencyItem]) -> Int {
        Set(items.compactMap { item in
            switch item.vcsInfo.state {
            case .dirty, .untrackedOnly:
                return item.projectRootPath
            case .clean, .notRepository, .notChecked, .checkFailed:
                return nil
            }
        }).count
    }

    private static func deduplicatedSkippedProjects(_ projects: [ProjectDependencyPolicySkippedProject]) -> [ProjectDependencyPolicySkippedProject] {
        var seen: Set<String> = []
        var output: [ProjectDependencyPolicySkippedProject] = []
        for project in projects.sorted(by: { lhs, rhs in
            if lhs.projectName == rhs.projectName {
                return lhs.projectRootPath < rhs.projectRootPath
            }
            return lhs.projectName < rhs.projectName
        }) {
            guard seen.insert(project.projectRootPath).inserted else { continue }
            output.append(project)
        }
        return output
    }

    private static func workspaceRootCount(for items: [ProjectDependencyItem]) -> Int {
        Set(items.compactMap(\.workspaceInfo.rootPath)).count
    }

    private static func parseGitStatus(_ output: String) -> (changedTracked: Int, untracked: Int) {
        var changedTracked = 0
        var untracked = 0
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("??") {
                untracked += 1
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                changedTracked += 1
            }
        }
        return (changedTracked, untracked)
    }

    private static func commandHints(for metadata: ProjectDependencyCandidateMetadata) -> [NativeToolCommand] {
        let hints = Set(metadata.manifestHints)
        let tooling = metadata.toolingInfo
        switch metadata.kind {
        case .nodeModules:
            var commands = [
                commandHint(
                    "project.javascript.install",
                    javascriptInstallCommand(for: hints, toolingInfo: tooling),
                    "Recreate project dependencies after reviewing lockfiles and local edits.",
                    .reclaim,
                    "Reinstalls project-local dependencies from the selected package manager."
                )
            ]
            if let clean = javascriptScriptCommand(for: tooling, hints: hints, preferredScripts: ["clean"], id: "project.javascript.script.clean", purpose: "Project-defined clean script detected; review it before using it for project-local cleanup.", risk: .inspect, expectedEffect: "Runs the project's own clean script; exact effect depends on package.json.") {
                commands.append(clean)
            }
            return commands
        case .webBuildOutput, .webFrameworkCache:
            var commands = [
                commandHint(
                    "project.javascript.install",
                    javascriptInstallCommand(for: hints, toolingInfo: tooling),
                    "Restore dependencies needed to rebuild project-local web artifacts.",
                    .reclaim,
                    "Recreates project-local dependencies if they were removed."
                )
            ]
            if let build = javascriptScriptCommand(for: tooling, hints: hints, preferredScripts: ["build", "compile", "generate", "export"], id: "project.javascript.script.build", purpose: "Project-defined build script detected for regenerating web output.", risk: .inspect, expectedEffect: "Regenerates project-local build output according to package.json.") {
                commands.append(build)
            }
            if let clean = javascriptScriptCommand(for: tooling, hints: hints, preferredScripts: ["clean"], id: "project.javascript.script.clean", purpose: "Project-defined clean script detected for project artifacts.", risk: .inspect, expectedEffect: "Runs the project's own clean script; exact effect depends on package.json.") {
                commands.append(clean)
            }
            return commands
        case .coverageOutput:
            return javascriptScriptCommand(for: tooling, hints: hints, preferredScripts: ["coverage", "test:coverage", "test"], id: "project.javascript.script.coverage", purpose: "Project-defined coverage/test script detected for regenerating coverage output.", risk: .inspect, expectedEffect: "Runs the selected package.json script; coverage output depends on project configuration.").map { [$0] } ?? []
        case .pythonVirtualEnvironment:
            return [
                commandHint(
                    "project.python.venv",
                    pythonVirtualEnvironmentCommand(for: hints),
                    "Recreate the virtual environment after reviewing Python manifests.",
                    .reclaim,
                    "Creates a fresh project-local virtual environment and installs declared dependencies when a manifest is present."
                )
            ]
        case .swiftBuild:
            return [
                commandHint(
                    "project.swift.clean",
                    "swift package clean",
                    "Let SwiftPM remove project build artifacts after active builds finish.",
                    .reclaim,
                    "Removes SwiftPM build output for the current package."
                ),
                commandHint(
                    "project.swift.build",
                    "swift build --scratch-path .build",
                    "Rebuild while keeping future autonomous build output bounded to the project directory.",
                    .inspect,
                    "Recreates build artifacts inside .build."
                )
            ]
        case .rustTarget:
            return [
                commandHint(
                    "project.rust.clean",
                    "cargo clean",
                    "Let Cargo remove project target artifacts after active builds finish.",
                    .reclaim,
                    "Removes the current project's target output."
                ),
                commandHint(
                    "project.rust.build",
                    "cargo build",
                    "Rebuild the project after cleanup.",
                    .inspect,
                    "Regenerates target artifacts."
                )
            ]
        case .gradleProjectCache, .gradleBuildOutput:
            return [
                commandHint(
                    "project.gradle.clean",
                    "./gradlew clean",
                    "Let Gradle remove project build output after active daemons finish.",
                    .reclaim,
                    "Removes Gradle project build outputs without raw-deleting source or config."
                )
            ]
        case .cocoaPodsPods:
            return [
                commandHint(
                    "project.cocoapods.install",
                    "pod install",
                    "Restore Pods after checking for local pod edits.",
                    .reclaim,
                    "Recreates Pods from the Podfile and lockfile when available."
                )
            ]
        case .dartTool:
            return [
                commandHint(
                    "project.dart.pub-get",
                    "dart pub get",
                    "Regenerate Dart package configuration after review.",
                    .reclaim,
                    "Restores .dart_tool package metadata from pubspec files."
                )
            ]
        case .androidBuild:
            if metadata.ecosystem == .dartFlutter {
                return [
                    commandHint(
                        "project.flutter.clean",
                        "flutter clean",
                        "Let Flutter remove project build artifacts after active tools finish.",
                        .reclaim,
                        "Removes Flutter build output and generated state."
                    ),
                    commandHint(
                        "project.flutter.pub-get",
                        "flutter pub get",
                        "Restore Flutter/Dart package metadata after cleanup.",
                        .reclaim,
                        "Regenerates package configuration from pubspec files."
                    )
                ]
            }
            return [
                commandHint(
                    "project.android.clean",
                    "./gradlew clean",
                    "Let Gradle/Android remove project build output after active tools finish.",
                    .reclaim,
                    "Removes Android project build outputs without raw-deleting source or manifests."
                )
            ]
        case .goBuildOutput:
            return [
                commandHint(
                    "project.go.build",
                    "go build ./...",
                    "Rebuild Go outputs after review.",
                    .inspect,
                    "Regenerates Go build output according to the project command."
                )
            ]
        case .other:
            return []
        }
    }

    private static func commandHint(
        _ id: String,
        _ command: String,
        _ purpose: String,
        _ risk: NativeToolRisk,
        _ expectedEffect: String
    ) -> NativeToolCommand {
        NativeToolCommand(
            id: id,
            command: command,
            purpose: purpose,
            risk: risk,
            requiresReview: true,
            expectedEffect: expectedEffect
        )
    }

    private static func javascriptInstallCommand(for hints: Set<String>, toolingInfo: ProjectDependencyToolingInfo) -> String {
        switch toolingInfo.toolName?.lowercased() {
        case "pnpm":
            return "pnpm install --frozen-lockfile"
        case "yarn":
            if let major = toolingInfo.toolVersion.flatMap(majorVersion), major >= 2 {
                return "yarn install --immutable"
            }
            return "yarn install"
        case "bun":
            return "bun install --frozen-lockfile"
        case "npm":
            return hints.contains("package-lock.json") || hints.contains("npm-shrinkwrap.json") ? "npm ci" : "npm install"
        default:
            break
        }
        if hints.contains("pnpm-lock.yaml") {
            return "pnpm install --frozen-lockfile"
        }
        if hints.contains("yarn.lock") {
            return "yarn install"
        }
        if hints.contains("bun.lock") || hints.contains("bun.lockb") {
            return "bun install --frozen-lockfile"
        }
        if hints.contains("package-lock.json") || hints.contains("npm-shrinkwrap.json") {
            return "npm ci"
        }
        return "npm install"
    }

    private static func javascriptRunCommand(for toolingInfo: ProjectDependencyToolingInfo, hints: Set<String>, script: String) -> String {
        switch toolingInfo.toolName?.lowercased() {
        case "pnpm":
            return "pnpm run \(script)"
        case "yarn":
            return "yarn \(script)"
        case "bun":
            return "bun run \(script)"
        case "npm":
            return "npm run \(script)"
        default:
            break
        }
        if hints.contains("pnpm-lock.yaml") {
            return "pnpm run \(script)"
        }
        if hints.contains("yarn.lock") {
            return "yarn \(script)"
        }
        if hints.contains("bun.lock") || hints.contains("bun.lockb") {
            return "bun run \(script)"
        }
        return "npm run \(script)"
    }

    private static func javascriptScriptCommand(
        for toolingInfo: ProjectDependencyToolingInfo,
        hints: Set<String>,
        preferredScripts: [String],
        id: String,
        purpose: String,
        risk: NativeToolRisk,
        expectedEffect: String
    ) -> NativeToolCommand? {
        guard let script = preferredScripts.first(where: { toolingInfo.packageScripts.contains($0) }) else {
            return nil
        }
        return commandHint(
            "\(id).\(signalToken(script))",
            javascriptRunCommand(for: toolingInfo, hints: hints, script: script),
            purpose,
            risk,
            expectedEffect
        )
    }

    private static func pythonVirtualEnvironmentCommand(for hints: Set<String>) -> String {
        if hints.contains("requirements.txt") {
            return "python3 -m venv .venv && .venv/bin/python -m pip install -r requirements.txt"
        }
        if hints.contains("pyproject.toml") || hints.contains("setup.py") {
            return "python3 -m venv .venv && .venv/bin/python -m pip install -e ."
        }
        if hints.contains("Pipfile") {
            return "python3 -m venv .venv && .venv/bin/python -m pip install pipenv && .venv/bin/python -m pipenv install"
        }
        return "python3 -m venv .venv"
    }

    private static func recommendation(for metadata: ProjectDependencyCandidateMetadata, isOld: Bool) -> String {
        let ageText = isOld ? " This item is older than the configured review threshold." : ""
        return "\(metadata.ecosystem.nativeCleanupHint) Review VCS status and active tools before removing \(metadata.kind.label).\(ageText)"
    }

    private static func itemGuidance(
        for metadata: ProjectDependencyCandidateMetadata,
        isOld: Bool,
        isSymbolicLink: Bool,
        policyRule: ProjectDependencyProjectPolicy?,
        policySkipOverridden: Bool
    ) -> [String] {
        var guidance = [
            "Project Dependency Review is report-only; this item is not selected for cleanup.",
            "Confirm the project has the expected manifests/lockfiles and no local generated edits before cleanup.",
            metadata.ecosystem.nativeCleanupHint
        ]
        switch metadata.kind {
        case .nodeModules, .webBuildOutput, .webFrameworkCache, .coverageOutput:
            guidance.append("Common recovery path: stop dev servers, remove the artifact manually if desired, then run the project's package-manager install/build command.")
        case .pythonVirtualEnvironment:
            guidance.append("Common recovery path: recreate the virtual environment from pyproject.toml, requirements.txt, Pipfile, or poetry.lock.")
        case .swiftBuild:
            guidance.append("Common recovery path: run `swift package clean` or remove .build after quitting Swift/Xcode builds; the next build recreates it.")
        case .rustTarget:
            guidance.append("Common recovery path: run `cargo clean`; the next Cargo build recreates target.")
        case .gradleProjectCache, .gradleBuildOutput, .androidBuild:
            guidance.append("Common recovery path: use Gradle or Android Studio cleanup; expect a slower next sync/build.")
        case .cocoaPodsPods:
            guidance.append("Common recovery path: review for local pod edits first, then use CocoaPods commands such as `pod install`.")
        case .dartTool:
            guidance.append("Common recovery path: use `flutter clean` or `dart pub get`; expect regenerated package config.")
        case .goBuildOutput:
            guidance.append("Common recovery path: rebuild Go project outputs with the owning build command.")
        case .other:
            guidance.append("Use the owning tool's project documentation before cleanup.")
        }
        if isOld {
            guidance.append("Old modification time is review evidence, not cleanup permission.")
        }
        if isSymbolicLink {
            guidance.append("Symbolic link was not followed while measuring.")
        }
        if metadata.toolingInfo.toolName != nil {
            guidance.append("Detected project tool: \(metadata.toolingInfo.toolLabel)\(metadata.toolingInfo.toolSource.map { " from \($0)" } ?? "").")
        }
        if !metadata.toolingInfo.packageScripts.isEmpty {
            guidance.append("Detected package.json scripts for review: \(metadata.toolingInfo.packageScripts.prefix(12).joined(separator: ", ")).")
        }
        if metadata.workspaceInfo.isWorkspace {
            guidance.append("Workspace context detected: \(metadata.workspaceInfo.label). Review workspace-level dependency hoisting, shared scripts, and sibling packages before cleanup.")
            if !metadata.workspaceInfo.packagePatterns.isEmpty {
                guidance.append("Workspace package patterns: \(metadata.workspaceInfo.packagePatterns.prefix(12).joined(separator: ", ")).")
            }
        }
        for note in metadata.toolingInfo.notes.prefix(3) {
            guidance.append(note)
        }
        if let policyRule {
            guidance.append(policyRule.decision.guidance)
            if let reason = policyRule.reason {
                guidance.append("Saved project policy reason: \(reason)")
            }
            if policySkipOverridden {
                guidance.append("Saved skip-review policy was overridden for this report.")
            }
        }
        return guidance
    }

    private static func shouldSkipTraversal(name: String) -> Bool {
        let lower = name.lowercased()
        return lower == ".git"
            || lower == ".hg"
            || lower == ".svn"
            || lower == ".jj"
            || lower == ".idea"
            || lower == ".vscode"
            || lower == ".cursor"
            || lower == ".windsurf"
    }

    private static func hasJavaScriptHint(_ hints: Set<String>) -> Bool {
        !hints.isDisjoint(with: ["package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb", "npm-shrinkwrap.json"])
    }

    private static func hasGradleHint(_ hints: Set<String>) -> Bool {
        !hints.isDisjoint(with: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "gradlew", "pom.xml"])
    }

    private static func hasAndroidHint(_ hints: Set<String>) -> Bool {
        hasGradleHint(hints)
            && (hints.contains("app/src/main/AndroidManifest.xml") || hints.contains("src/main/AndroidManifest.xml"))
    }

    private static func fallbackTool(for hints: Set<String>) -> (name: String, source: String)? {
        if hints.contains("pnpm-workspace.yaml") {
            return ("pnpm", "pnpm-workspace.yaml")
        }
        if hints.contains("pnpm-lock.yaml") {
            return ("pnpm", "pnpm-lock.yaml")
        }
        if hints.contains("yarn.lock") {
            return ("yarn", "yarn.lock")
        }
        if hints.contains("bun.lock") || hints.contains("bun.lockb") {
            return ("bun", hints.contains("bun.lock") ? "bun.lock" : "bun.lockb")
        }
        if hints.contains("package-lock.json") || hints.contains("npm-shrinkwrap.json") || hints.contains("package.json") {
            return ("npm", hints.contains("package-lock.json") ? "package-lock.json" : "package.json")
        }
        if hints.contains("poetry.lock") {
            return ("poetry", "poetry.lock")
        }
        if hints.contains("Pipfile") {
            return ("pipenv", "Pipfile")
        }
        if hints.contains("requirements.txt") || hints.contains("pyproject.toml") || hints.contains("setup.py") {
            return ("pip", "Python manifest")
        }
        if hints.contains("Package.swift") {
            return ("SwiftPM", "Package.swift")
        }
        if hints.contains("Cargo.toml") || hints.contains("Cargo.lock") {
            return ("Cargo", "Cargo.toml")
        }
        if hasGradleHint(hints) {
            return (hints.contains("gradlew") ? "Gradle wrapper" : "Gradle", "Gradle manifest")
        }
        if hints.contains("Podfile") || hints.contains("Podfile.lock") {
            return ("CocoaPods", "Podfile")
        }
        if hints.contains("pubspec.yaml") || hints.contains("pubspec.lock") {
            return ("Flutter/Dart", "pubspec.yaml")
        }
        if hints.contains("go.mod") || hints.contains("go.sum") {
            return ("Go", "go.mod")
        }
        return nil
    }

    private static func workspaceKind(forPackageManager name: String) -> ProjectDependencyWorkspaceKind {
        switch name.lowercased() {
        case "pnpm":
            return .pnpm
        case "yarn":
            return .yarn
        case "bun":
            return .bun
        case "npm":
            return .npm
        default:
            return .javascript
        }
    }

    private static func parsePackageManagerField(_ value: String) -> (name: String, version: String?)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard isSafePackageScriptName(name), !name.isEmpty else { return nil }
        let version = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
        return (name, version)
    }

    private static func safeWorkspacePatterns(_ values: [Any]) -> [String] {
        Array(Set(values.compactMap { value -> String? in
            guard let string = value as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafeWorkspacePattern(trimmed) else { return nil }
            return trimmed
        })).sorted().prefixArray(50)
    }

    private static func isSafeWorkspacePattern(_ pattern: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./*@{}!,"))
        return !pattern.isEmpty
            && pattern.count <= 200
            && !pattern.contains("..")
            && pattern.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafePackageScriptName(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:."))
        return !name.isEmpty && name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func majorVersion(_ version: String) -> Int? {
        let digits = version.split(separator: ".").first?.prefix { $0.isNumber } ?? ""
        return Int(digits)
    }

    private static func signalToken(_ value: String) -> String {
        value.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }.reduce(into: "") { partial, character in
            if character == "-", partial.last == "-" {
                return
            }
            partial.append(character)
        }.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static let webFrameworkCacheNames: Set<String> = [
        ".next",
        ".nuxt",
        ".svelte-kit",
        ".turbo",
        ".parcel-cache",
        ".vite",
        ".cache"
    ]

    private static let webBuildOutputNames: Set<String> = [
        "dist",
        "out",
        "build"
    ]

    private static let manifestFiles: [String] = [
        "package.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "pnpm-workspace.yaml",
        "yarn.lock",
        "bun.lock",
        "bun.lockb",
        "npm-shrinkwrap.json",
        "pyproject.toml",
        "requirements.txt",
        "setup.py",
        "Pipfile",
        "poetry.lock",
        "Package.swift",
        "Cargo.toml",
        "Cargo.lock",
        "build.gradle",
        "build.gradle.kts",
        "settings.gradle",
        "settings.gradle.kts",
        "gradlew",
        "pom.xml",
        "Podfile",
        "Podfile.lock",
        "pubspec.yaml",
        "pubspec.lock",
        "go.mod",
        "go.sum",
        "lerna.json",
        "turbo.json",
        "nx.json",
        "rush.json"
    ]

    private static let nestedManifestPaths: [String] = [
        "app/src/main/AndroidManifest.xml",
        "src/main/AndroidManifest.xml"
    ]

    public static let guidance = [
        "Review project status, VCS changes, lockfiles, and active terminals before cleanup.",
        "Use saved project policies to mark recurring projects for review, preserve-by-default, or skip-review; policies do not grant cleanup permission.",
        "Use workspace/monorepo evidence to review dependency hoisting, shared package-manager commands, and sibling packages before removing project-local artifacts.",
        "Prefer detected package-manager and project-script commands such as package-manager install/clean, `swift package clean`, `cargo clean`, `./gradlew clean`, `flutter clean`, or `pod install` over blind deletion.",
        "Skip active builds, dev servers, simulators, IDE indexing, and terminals using the project.",
        "Treat project-local dependencies as rebuildable evidence only when the project has the expected manifests and network/toolchain access."
    ]

    public static let nonClaims = [
        "Project Dependency Review is report-only; it does not delete, move, Trash, prune, purge, clean, or modify project files.",
        "Saved Project Dependencies policies only annotate or skip report rows; they do not make project dependencies safe to delete.",
        "Detected package managers and package.json scripts are guidance evidence only; Ryddi does not execute project scripts or prove they are safe.",
        "Detected workspace and monorepo metadata is guidance evidence only; Ryddi does not prove workspace scripts, hoisted dependencies, or sibling-package state are safe to remove.",
        "Ryddi does not measure project source, manifests, lockfiles, env files, credentials, IDE settings, or unknown project state as cleanup candidates.",
        "Project-local dependency and build directories may contain generated code, local editable installs, offline dependencies, or unsaved development state; review the project before cleanup.",
        "Classification is path-and-manifest based and cannot prove the owning tool is idle or that all active handles are closed.",
        "Reported project dependency size is not promised immediate free-space recovery because APFS snapshots, clones, hard links, sparse files, and purgeable storage can affect accounting."
    ]
}

private struct ProjectDependencyCandidateMetadata: Hashable {
    let projectRoot: URL
    let manifestHints: [String]
    let toolingInfo: ProjectDependencyToolingInfo
    let workspaceInfo: ProjectDependencyWorkspaceInfo
    let ecosystem: ProjectDependencyEcosystem
    let kind: ProjectDependencyKind
}

private struct ProjectDependencyMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

private struct ProjectDependencyGitStatusResult: Hashable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private let projectDependencyResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(Swift.max(0, maxLength)))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
