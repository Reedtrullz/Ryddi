import Foundation

public struct ScanOptions: Hashable, Sendable {
    public let minimumFindingSize: Int64
    public let maximumFindingDepth: Int
    public let measurementDepth: Int
    public let includeOpenFileStatus: Bool
    public let largeFileThreshold: Int64
    public let oldFileAgeDays: Int
    public let userPathPolicy: UserPathPolicy
    public let measurementItemBudget: Int
    public let deduplicateHardLinks: Bool

    public init(
        minimumFindingSize: Int64 = 1_000_000,
        maximumFindingDepth: Int = 2,
        measurementDepth: Int = 8,
        includeOpenFileStatus: Bool = false,
        largeFileThreshold: Int64 = 5_000_000_000,
        oldFileAgeDays: Int = 180,
        userPathPolicy: UserPathPolicy = .empty,
        measurementItemBudget: Int = 25_000,
        deduplicateHardLinks: Bool = true
    ) {
        self.minimumFindingSize = minimumFindingSize
        self.maximumFindingDepth = maximumFindingDepth
        self.measurementDepth = measurementDepth
        self.includeOpenFileStatus = includeOpenFileStatus
        self.largeFileThreshold = largeFileThreshold
        self.oldFileAgeDays = oldFileAgeDays
        self.userPathPolicy = userPathPolicy
        self.measurementItemBudget = max(1, min(measurementItemBudget, 2_000_000))
        self.deduplicateHardLinks = deduplicateHardLinks
    }
}

struct FileMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

struct ScanCancellationToken: Sendable {
    let isCancelled = false
}

struct ScanControl: Sendable {
    let cancellation: ScanCancellationToken

    static let none = ScanControl(cancellation: ScanCancellationToken())
}

public final class FileScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let ruleEngine: RuleEngine
    private let openFileChecker: OpenFileChecking
    private let scopeReadabilityProvider: (URL, FileManager) -> ScopeReadability

    public convenience init(
        fileManager: FileManager = .default,
        ruleEngine: RuleEngine? = nil,
        openFileChecker: OpenFileChecking = LsofOpenFileChecker()
    ) throws {
        try self.init(
            fileManager: fileManager,
            ruleEngine: ruleEngine,
            openFileChecker: openFileChecker,
            scopeReadabilityProvider: { root, fileManager in
                PermissionAdvisor.scopeReadability(at: root, fileManager: fileManager)
            }
        )
    }

    init(
        fileManager: FileManager = .default,
        ruleEngine: RuleEngine? = nil,
        openFileChecker: OpenFileChecking = LsofOpenFileChecker(),
        scopeReadabilityProvider: @escaping (URL, FileManager) -> ScopeReadability
    ) throws {
        self.fileManager = fileManager
        self.ruleEngine = try ruleEngine ?? RuleEngine.bundled()
        self.openFileChecker = openFileChecker
        self.scopeReadabilityProvider = scopeReadabilityProvider
    }

    public func scan(scopes: [ScanScope], options: ScanOptions = ScanOptions()) -> [Finding] {
        scanWithCoverage(scopes: scopes, options: options).findings
    }

    public func scanWithCoverage(scopes: [ScanScope], options: ScanOptions = ScanOptions()) -> ScanResult {
        let tree = BoundedFileTreeWalker(scopeReadabilityProvider: scopeReadabilityProvider).walk(
            scopes: scopes,
            options: options,
            fileManager: fileManager,
            userPathPolicy: options.userPathPolicy,
            control: .none
        )
        var findings = tree.nodes.compactMap { node -> Finding? in
            guard node.absoluteDepth <= max(0, options.maximumFindingDepth) else { return nil }
            return makeFinding(
                scope: scopes[node.scopeIndex],
                node: node,
                options: options
            )
        }
        findings.append(contentsOf: tree.scopeIssues.map { issue in
            permissionFinding(
                scope: scopes[issue.scopeIndex],
                state: issue.state,
                message: issue.message
            )
        })
        findings.sort { lhs, rhs in
            if lhs.allocatedSize == rhs.allocatedSize {
                return lhs.path < rhs.path
            }
            return lhs.allocatedSize > rhs.allocatedSize
        }
        let coveredFindings = findings.map { $0.withMeasurementCoverage(tree.coverage.state.rawValue) }
        return ScanResult(findings: coveredFindings, coverage: tree.coverage)
    }

    private func makeFinding(scope: ScanScope, node: BoundedFileTree.Node, options: ScanOptions) -> Finding {
        let url = node.url
        let isDirectory = node.resource.isDirectory
        let isSymbolicLink = node.resource.isSymbolicLink
        let measurement = node.boundedMeasurement
        let classification = ruleEngine.classify(path: url.path, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink)
        let openStatus = options.includeOpenFileStatus ? openFileChecker.status(for: url) : nil
        let filesystemIdentity = try? FilesystemIdentity.capture(at: url)

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
            depth: node.absoluteDepth,
            measurement: measurement,
            modificationDate: node.resource.modificationDate,
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
        if node.absoluteDepth == 0 {
            evidence.append(Evidence(kind: "scope", message: "Scan root: \(scope.name)."))
        }

        let storageAccounting = StorageAccounting(
            logicalBytes: measurement.logicalSize,
            allocatedBytes: measurement.allocatedSize,
            physicalReclaimStatus: (filesystemIdentity?.hardLinkCount ?? 1) > 1 ? .sharedCloneBacked : .estimated,
            deduplicationNote: (filesystemIdentity?.hardLinkCount ?? 1) > 1
                ? "This regular file has multiple hard links; allocated bytes are shared identity evidence, not an independent reclaim promise."
                : "Allocated bytes are an estimate; verify observed free-space change after any confirmed action."
        )

        return Finding(
            scopeName: scope.name,
            path: url.path,
            displayName: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            modificationDate: node.resource.modificationDate,
            filesystemIdentity: filesystemIdentity,
            ownerHint: ownerHint(for: url.path),
            safetyClass: safetyClass,
            actionKind: actionKind,
            ruleMatches: matches,
            evidence: evidence,
            openFileStatus: openStatus,
            storageAccounting: storageAccounting
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

private func ownerHint(for path: String) -> String? {
    let lower = path.lowercased()
    if lower.contains("/.codex") ||
        lower.contains("com.openai.codex") ||
        lower.contains("/library/caches/codex") ||
        lower.contains("/library/logs/codex")
    {
        return "Codex"
    }
    if lower.contains("/.claude") || lower.contains("/application support/claude") {
        return "Claude"
    }
    if lower.contains("/application support/cursor") { return "Cursor" }
    if lower.contains("/application support/windsurf") { return "Windsurf" }
    if lower.contains("/.ollama") { return "Ollama" }
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
    public static func plan(
        for preset: ScanScopePreset = .developer,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) -> ScanScopePlan {
        ScanScopePlan(
            preset: preset,
            label: preset.label,
            summary: preset.summary,
            scopes: scopes(for: preset, home: home, includeUnavailable: includeUnavailable),
            nonClaims: nonClaims(for: preset)
        )
    }

    public static func customPlan(
        label: String = "Custom paths",
        summary: String = "Explicit paths supplied by the user override preset scan roots.",
        scopes: [ScanScope],
        nonClaims: [String] = [
            "Custom paths do not change Ryddi's safety rules or cleanup protections.",
            "Scanning a path does not mean Ryddi will select it for cleanup.",
            "Permission state is checked separately when the scan or permission advisor runs."
        ]
    ) -> ScanScopePlan {
        ScanScopePlan(
            preset: nil,
            label: label,
            summary: summary,
            scopes: uniqueScopes(scopes),
            nonClaims: nonClaims
        )
    }

    public static func scopes(
        for preset: ScanScopePreset = .developer,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) -> [ScanScope] {
        switch preset {
        case .developer:
            return developerAgentBloat(home: home, includeUnavailable: includeUnavailable)
        case .general:
            return generalMacCleanup(home: home, includeUnavailable: includeUnavailable)
        case .all:
            let combined = generalMacCleanup(home: home, includeUnavailable: includeUnavailable)
                + developerAgentBloat(home: home, includeUnavailable: includeUnavailable)
            return uniqueScopes(combined, removingNestedChildren: true)
        }
    }

    public static func developerAgentBloat(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) -> [ScanScope] {
        let paths: [(String, URL)] = [
            ("Codex state", home.appendingPathComponent(".codex")),
            ("Codex desktop logs", home.appendingPathComponent("Library/Logs/com.openai.codex")),
            ("Codex app cache", home.appendingPathComponent("Library/Caches/Codex")),
            ("Claude state", home.appendingPathComponent(".claude")),
            ("Claude app support", home.appendingPathComponent("Library/Application Support/Claude")),
            ("Ollama models", home.appendingPathComponent(".ollama")),
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
        return scopes(from: paths, includeUnavailable: includeUnavailable)
    }

    public static func aiAgentStorage(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) -> [ScanScope] {
        let paths: [(String, URL)] = [
            ("Codex state", home.appendingPathComponent(".codex")),
            ("Codex desktop logs", home.appendingPathComponent("Library/Logs/com.openai.codex")),
            ("Codex app cache", home.appendingPathComponent("Library/Caches/Codex")),
            ("Claude state", home.appendingPathComponent(".claude")),
            ("Claude app support", home.appendingPathComponent("Library/Application Support/Claude")),
            ("Cursor app support", home.appendingPathComponent("Library/Application Support/Cursor")),
            ("Windsurf app support", home.appendingPathComponent("Library/Application Support/Windsurf")),
            ("Ollama models", home.appendingPathComponent(".ollama"))
        ]
        return scopes(from: paths, includeUnavailable: includeUnavailable)
    }

    public static func generalMacCleanup(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeUnavailable: Bool = false
    ) -> [ScanScope] {
        let paths: [(String, URL)] = [
            ("Downloads review", home.appendingPathComponent("Downloads")),
            ("Desktop review", home.appendingPathComponent("Desktop")),
            ("Documents review", home.appendingPathComponent("Documents")),
            ("Movies review", home.appendingPathComponent("Movies")),
            ("Pictures review", home.appendingPathComponent("Pictures")),
            ("Music review", home.appendingPathComponent("Music")),
            ("User caches", home.appendingPathComponent("Library/Caches")),
            ("User logs", home.appendingPathComponent("Library/Logs")),
            ("Application Support review", home.appendingPathComponent("Library/Application Support")),
            ("Mail downloads review", home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")),
            ("Messages attachments review", home.appendingPathComponent("Library/Messages/Attachments")),
            ("Device backups review", home.appendingPathComponent("Library/Application Support/MobileSync/Backup")),
            ("Trash review", home.appendingPathComponent(".Trash"))
        ]
        return scopes(from: paths, includeUnavailable: includeUnavailable, removingNestedChildren: true)
    }

    private static func scopes(
        from paths: [(String, URL)],
        includeUnavailable: Bool,
        removingNestedChildren: Bool = false
    ) -> [ScanScope] {
        uniqueScopes(paths.compactMap { name, url in
            let root = url.standardizedFileURL
            if includeUnavailable || FileManager.default.fileExists(atPath: root.path) {
                return ScanScope(name: name, root: root, permissionState: .unknown)
            }
            return nil
        }, removingNestedChildren: removingNestedChildren)
    }

    private static func uniqueScopes(_ scopes: [ScanScope], removingNestedChildren: Bool = false) -> [ScanScope] {
        var seen: Set<String> = []
        let unique = scopes.compactMap { scope -> ScanScope? in
            let path = normalized(scope.root.path)
            guard seen.insert(path).inserted else { return nil }
            return scope
        }

        guard removingNestedChildren else {
            return unique
        }

        return unique.filter { candidate in
            !unique.contains { other in
                normalized(other.root.path) != normalized(candidate.root.path)
                    && isAncestor(other.root, of: candidate.root)
            }
        }
    }

    private static func normalized(_ path: String) -> String {
        var value = URL(fileURLWithPath: path).standardizedFileURL.path
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func isAncestor(_ parent: URL, of child: URL) -> Bool {
        let parentComponents = URL(fileURLWithPath: normalized(parent.path)).pathComponents
        let childComponents = URL(fileURLWithPath: normalized(child.path)).pathComponents
        guard childComponents.count > parentComponents.count else { return false }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }

    private static func nonClaims(for preset: ScanScopePreset) -> [String] {
        var notes = [
            "Preset scopes define where Ryddi looks; rules and user policy still decide what can be planned or blocked.",
            "Scanning personal folders is review-oriented and does not grant cleanup permission.",
            "Permission coverage can be degraded without Full Disk Access, and missing scopes are reported rather than assumed clean."
        ]
        if preset == .all {
            notes.append("Overlapping child scopes are collapsed in the All preset to reduce double-counted findings.")
        }
        return notes
    }
}
