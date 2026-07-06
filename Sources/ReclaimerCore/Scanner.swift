import Foundation

public struct ScanOptions: Hashable, Sendable {
    public let minimumFindingSize: Int64
    public let maximumFindingDepth: Int
    public let measurementDepth: Int
    public let includeOpenFileStatus: Bool
    public let largeFileThreshold: Int64
    public let oldFileAgeDays: Int
    public let userPathPolicy: UserPathPolicy

    public init(
        minimumFindingSize: Int64 = 1_000_000,
        maximumFindingDepth: Int = 2,
        measurementDepth: Int = 8,
        includeOpenFileStatus: Bool = false,
        largeFileThreshold: Int64 = 5_000_000_000,
        oldFileAgeDays: Int = 180,
        userPathPolicy: UserPathPolicy = .empty
    ) {
        self.minimumFindingSize = minimumFindingSize
        self.maximumFindingDepth = maximumFindingDepth
        self.measurementDepth = measurementDepth
        self.includeOpenFileStatus = includeOpenFileStatus
        self.largeFileThreshold = largeFileThreshold
        self.oldFileAgeDays = oldFileAgeDays
        self.userPathPolicy = userPathPolicy
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
        if options.userPathPolicy.matchingRule(for: root.path, kind: .exclude) != nil {
            return []
        }

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
        if options.userPathPolicy.matchingRule(for: url.path, kind: .exclude) != nil {
            return
        }

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
        let measurement = measure(url: url, maxDepth: options.measurementDepth, userPathPolicy: options.userPathPolicy)
        let classification = ruleEngine.classify(path: url.path, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink)
        let openStatus = options.includeOpenFileStatus ? openFileChecker.status(for: url) : nil

        var safetyClass = classification.safetyClass
        var actionKind = classification.actionKind
        var matches = classification.matches
        var evidence = classification.evidence
        let isUserProtected: Bool
        if let protectedRule = options.userPathPolicy.matchingRule(for: url.path, kind: .protect) {
            isUserProtected = true
            let ruleMatch = userProtectedRuleMatch(for: protectedRule)
            matches.insert(ruleMatch, at: 0)
            evidence.insert(contentsOf: ruleMatch.evidence.map { Evidence(kind: ruleMatch.ruleID, message: $0) }, at: 0)
            if safetyClass != .neverTouch {
                safetyClass = .preserveByDefault
                actionKind = .reportOnly
            }
        } else {
            isUserProtected = false
        }
        let reviewSignals = dynamicReviewSignals(
            path: url.path,
            depth: depth,
            measurement: measurement,
            modificationDate: values?.contentModificationDate,
            classification: classification,
            options: options
        )
        if !reviewSignals.isEmpty {
            matches.append(contentsOf: reviewSignals)
            evidence.append(contentsOf: reviewSignals.flatMap { signal in
                signal.evidence.map { Evidence(kind: signal.ruleID, message: $0) }
            })
            if classification.matches.isEmpty && !isUserProtected {
                safetyClass = .reviewRequired
                actionKind = .openGuidance
            }
        }
        evidence.append(Evidence(kind: "size", message: "Allocated size: \(ByteFormat.string(measurement.allocatedSize)); logical size: \(ByteFormat.string(measurement.logicalSize))."))
        evidence.append(Evidence(kind: "accounting", message: storageAccountingNote(logicalSize: measurement.logicalSize, allocatedSize: measurement.allocatedSize)))
        evidence.append(Evidence(kind: "items", message: "Measured \(measurement.itemCount) item(s) within the configured scan depth."))
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
            safetyClass: safetyClass,
            actionKind: actionKind,
            ruleMatches: matches,
            evidence: evidence,
            openFileStatus: openStatus
        )
    }

    private func userProtectedRuleMatch(for rule: UserPathRule) -> RuleMatch {
        let reason = rule.reason.map { " Reason: \($0)" } ?? ""
        return RuleMatch(
            ruleID: "user.path.protected",
            title: "User-protected path",
            category: "User protection",
            safetyClass: .preserveByDefault,
            actionKind: .reportOnly,
            evidence: ["This path is covered by a user protection rule at \(rule.path).\(reason)"],
            conditions: ["Remove the user protection rule before cleanup can be considered."],
            recovery: "Protected paths stay visible for review but are not selected for cleanup."
        )
    }

    private func dynamicReviewSignals(
        path: String,
        depth: Int,
        measurement: FileMeasurement,
        modificationDate: Date?,
        classification: Classification,
        options: ScanOptions
    ) -> [RuleMatch] {
        guard depth > 0 else { return [] }
        guard classification.safetyClass == .reviewRequired || classification.matches.isEmpty else { return [] }

        var signals: [RuleMatch] = []
        if measurement.allocatedSize >= options.largeFileThreshold {
            signals.append(
                RuleMatch(
                    ruleID: "dynamic.large-item.review",
                    title: "Large item review",
                    category: "Large files",
                    safetyClass: .reviewRequired,
                    actionKind: .openGuidance,
                    evidence: ["This item is larger than \(ByteFormat.string(options.largeFileThreshold)); inspect it before deciding whether it is valuable or removable."],
                    conditions: ["Manual review only; use Finder or Quick Look before removing."],
                    recovery: "Move to Trash only after confirming it is not unique work, app state, or project data."
                )
            )
        }

        if let modificationDate {
            let age = Date().timeIntervalSince(modificationDate)
            let threshold = TimeInterval(options.oldFileAgeDays * 24 * 60 * 60)
            if age >= threshold, measurement.allocatedSize >= options.minimumFindingSize {
                signals.append(
                    RuleMatch(
                        ruleID: "dynamic.old-item.review",
                        title: "Old item review",
                        category: "Old files",
                        safetyClass: .reviewRequired,
                        actionKind: .openGuidance,
                        evidence: ["This item has not been modified for at least \(options.oldFileAgeDays) days."],
                        conditions: ["Manual review only; age is a signal, not permission to delete."],
                        recovery: "Move to Trash or archive only after confirming it is no longer needed."
                    )
                )
            }
        }

        return signals
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

    private func measure(url: URL, maxDepth: Int, userPathPolicy: UserPathPolicy) -> FileMeasurement {
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
            if userPathPolicy.matchingRule(for: child.path, kind: .exclude) != nil {
                enumerator.skipDescendants()
                continue
            }
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

private func storageAccountingNote(logicalSize: Int64, allocatedSize: Int64) -> String {
    if allocatedSize == logicalSize {
        return "Allocated and logical size are currently the same for this item."
    }
    if allocatedSize < logicalSize {
        return "Allocated size is lower than logical size; APFS clones, sparse files, compression, and purgeable data can make apparent size differ from immediate reclaim."
    }
    return "Allocated size is higher than logical size because physical blocks and filesystem metadata can add overhead."
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
    if lower.contains("/.codex") ||
        lower.contains("com.openai.codex") ||
        lower.contains("/library/caches/codex") ||
        lower.contains("/library/logs/codex")
    {
        return "Codex"
    }
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
    public static func developerAgentBloat(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) -> [ScanScope] {
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
            ("Gradle cache", home.appendingPathComponent(".gradle/caches")),
            ("Maven cache", home.appendingPathComponent(".m2/repository")),
            ("CocoaPods cache", home.appendingPathComponent("Library/Caches/CocoaPods")),
            ("SwiftPM cache", home.appendingPathComponent("Library/Caches/org.swift.swiftpm")),
            ("VS Code caches", home.appendingPathComponent("Library/Application Support/Code")),
            ("Cursor caches", home.appendingPathComponent("Library/Application Support/Cursor")),
            ("Windsurf caches", home.appendingPathComponent("Library/Application Support/Windsurf")),
            ("JetBrains caches", home.appendingPathComponent("Library/Caches/JetBrains")),
            ("Android Studio caches", home.appendingPathComponent("Library/Caches/Google/AndroidStudio")),
            ("Android SDK", home.appendingPathComponent("Library/Android/sdk")),
            ("Flutter pub cache", home.appendingPathComponent(".pub-cache")),
            ("Playwright browsers", home.appendingPathComponent("Library/Caches/ms-playwright")),
            ("Private temp", URL(fileURLWithPath: "/private/tmp"))
        ]
        return paths.compactMap { name, url in
            if includeUnavailable || FileManager.default.fileExists(atPath: url.path) {
                return ScanScope(name: name, root: url, permissionState: .unknown)
            }
            return nil
        }
    }
}
