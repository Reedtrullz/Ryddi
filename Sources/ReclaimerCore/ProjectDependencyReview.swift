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
    public let signals: [String]
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
        signals: [String],
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
        self.signals = signals
        self.recommendation = recommendation
        self.guidance = guidance
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
    public let note: String

    public init(
        id: String = UUID().uuidString,
        projectRootPath: String,
        projectName: String,
        manifestHints: [String],
        note: String
    ) {
        self.id = id
        self.projectRootPath = projectRootPath
        self.projectName = projectName
        self.manifestHints = manifestHints
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
    public let largestItems: [ProjectDependencyItem]
    public let protectedProjectRoots: [ProjectDependencyProtectedProjectRoot]
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
        largestItems: [ProjectDependencyItem],
        protectedProjectRoots: [ProjectDependencyProtectedProjectRoot],
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
        self.largestItems = largestItems
        self.protectedProjectRoots = protectedProjectRoots
        self.guidance = guidance
        self.nonClaims = nonClaims
    }
}

public struct ProjectDependencyReviewOptions: Hashable, Sendable {
    public let roots: [URL]
    public let limit: Int
    public let oldDays: Int
    public let maximumSearchDepth: Int
    public let measurementDepth: Int
    public let includeMissingRoots: Bool

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: [URL]? = nil,
        limit: Int = 50,
        oldDays: Int = 90,
        maximumSearchDepth: Int = 6,
        measurementDepth: Int = 8,
        includeMissingRoots: Bool = true
    ) {
        let standardizedHome = home.standardizedFileURL
        self.roots = (roots ?? Self.defaultRoots(home: standardizedHome)).map { $0.standardizedFileURL }
        self.limit = max(1, min(limit, 500))
        self.oldDays = max(1, min(oldDays, 3650))
        self.maximumSearchDepth = max(0, min(maximumSearchDepth, 24))
        self.measurementDepth = max(0, min(measurementDepth, 32))
        self.includeMissingRoots = includeMissingRoots
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

        for root in options.roots {
            let result = inspect(
                root: root,
                oldDays: options.oldDays,
                maximumSearchDepth: options.maximumSearchDepth,
                measurementDepth: options.measurementDepth,
                referenceDate: createdAt
            )
            if result.summary.permissionState != .missing || options.includeMissingRoots {
                summaries.append(result.summary)
            }
            items.append(contentsOf: result.items)
        }

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
            largestItems: Array(sortedItems.prefix(options.limit)),
            protectedProjectRoots: protectedProjectRoots(for: sortedItems),
            guidance: Self.guidance,
            nonClaims: Self.nonClaims
        )
    }

    private func inspect(
        root: URL,
        oldDays: Int,
        maximumSearchDepth: Int,
        measurementDepth: Int,
        referenceDate: Date
    ) -> (summary: ProjectDependencyRootSummary, items: [ProjectDependencyItem]) {
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
                []
            )
        }

        let items = projectDependencyItems(
            under: root,
            oldDays: oldDays,
            maximumSearchDepth: maximumSearchDepth,
            measurementDepth: measurementDepth,
            referenceDate: referenceDate
        )
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
                note: "Measured recognized project-local dependency and build artifact directories under \(root.path)."
            ),
            items
        )
    }

    private func projectDependencyItems(
        under root: URL,
        oldDays: Int,
        maximumSearchDepth: Int,
        measurementDepth: Int,
        referenceDate: Date
    ) -> [ProjectDependencyItem] {
        var items: [ProjectDependencyItem] = []

        if let values = try? root.resourceValues(forKeys: Set(projectDependencyResourceKeys)),
           values.isSymbolicLink != true,
           values.isDirectory == true,
           let metadata = candidateMetadata(for: root, boundary: root.deletingLastPathComponent().standardizedFileURL) {
            items.append(
                item(
                    for: root,
                    metadata: metadata,
                    values: values,
                    oldDays: oldDays,
                    measurementDepth: measurementDepth,
                    referenceDate: referenceDate
                )
            )
            return items
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: projectDependencyResourceKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return items
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
                items.append(
                    item(
                        for: child,
                        metadata: metadata,
                        values: values,
                        oldDays: oldDays,
                        measurementDepth: measurementDepth,
                        referenceDate: referenceDate
                    )
                )
                enumerator.skipDescendants()
            }
        }

        return items
    }

    private func item(
        for url: URL,
        metadata: ProjectDependencyCandidateMetadata,
        values: URLResourceValues,
        oldDays: Int,
        measurementDepth: Int,
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
            signals: signals,
            recommendation: Self.recommendation(for: metadata, isOld: isOld),
            guidance: Self.itemGuidance(for: metadata, isOld: isOld, isSymbolicLink: values.isSymbolicLink == true)
        )
    }

    private func candidateMetadata(for url: URL, boundary: URL) -> ProjectDependencyCandidateMetadata? {
        let name = url.lastPathComponent
        let lowerName = name.lowercased()
        let project = projectRoot(for: url, boundary: boundary)
        let hints = project.manifestHints
        let hintSet = Set(hints)

        func metadata(_ ecosystem: ProjectDependencyEcosystem, _ kind: ProjectDependencyKind) -> ProjectDependencyCandidateMetadata {
            ProjectDependencyCandidateMetadata(projectRoot: project.root, manifestHints: hints, ecosystem: ecosystem, kind: kind)
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

    private func projectRoot(for candidate: URL, boundary: URL) -> (root: URL, manifestHints: [String]) {
        let boundary = boundary.standardizedFileURL
        var current = candidate.deletingLastPathComponent().standardizedFileURL
        var fallback = current
        while true {
            let hints = manifestHints(at: current)
            if !hints.isEmpty {
                return (current, hints)
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
        return (fallback, manifestHints(at: fallback))
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
                    note: "Protected project files, source, manifests, lockfiles, env files, IDE settings, credentials, and unknown project state are intentionally not measured as cleanup candidates. \(manifestText)"
                )
            }
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

    private static func recommendation(for metadata: ProjectDependencyCandidateMetadata, isOld: Bool) -> String {
        let ageText = isOld ? " This item is older than the configured review threshold." : ""
        return "\(metadata.ecosystem.nativeCleanupHint) Review VCS status and active tools before removing \(metadata.kind.label).\(ageText)"
    }

    private static func itemGuidance(
        for metadata: ProjectDependencyCandidateMetadata,
        isOld: Bool,
        isSymbolicLink: Bool
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
        "go.sum"
    ]

    private static let nestedManifestPaths: [String] = [
        "app/src/main/AndroidManifest.xml",
        "src/main/AndroidManifest.xml"
    ]

    public static let guidance = [
        "Review project status, VCS changes, lockfiles, and active terminals before cleanup.",
        "Prefer native commands such as package-manager install/clean, `swift package clean`, `cargo clean`, `./gradlew clean`, `flutter clean`, or `pod install` over blind deletion.",
        "Skip active builds, dev servers, simulators, IDE indexing, and terminals using the project.",
        "Treat project-local dependencies as rebuildable evidence only when the project has the expected manifests and network/toolchain access."
    ]

    public static let nonClaims = [
        "Project Dependency Review is report-only; it does not delete, move, Trash, prune, purge, clean, or modify project files.",
        "Ryddi does not measure project source, manifests, lockfiles, env files, credentials, IDE settings, or unknown project state as cleanup candidates.",
        "Project-local dependency and build directories may contain generated code, local editable installs, offline dependencies, or unsaved development state; review the project before cleanup.",
        "Classification is path-and-manifest based and cannot prove the owning tool is idle or that all active handles are closed.",
        "Reported project dependency size is not promised immediate free-space recovery because APFS snapshots, clones, hard links, sparse files, and purgeable storage can affect accounting."
    ]
}

private struct ProjectDependencyCandidateMetadata: Hashable {
    let projectRoot: URL
    let manifestHints: [String]
    let ecosystem: ProjectDependencyEcosystem
    let kind: ProjectDependencyKind
}

private struct ProjectDependencyMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

private let projectDependencyResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]
