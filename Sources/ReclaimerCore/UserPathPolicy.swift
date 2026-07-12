import Foundation

public enum UserPathPolicyKind: String, Codable, CaseIterable, Hashable, Sendable {
    case exclude
    case protect

    public var label: String {
        switch self {
        case .exclude: "Exclude from scans"
        case .protect: "Protect from cleanup"
        }
    }
}

public struct UserPathRule: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: UserPathPolicyKind
    public let path: String
    public let reason: String?
    public let includeDescendants: Bool
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: UserPathPolicyKind,
        path: String,
        reason: String? = nil,
        includeDescendants: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.path = UserPathPolicy.standardizedPath(path)
        self.reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.includeDescendants = includeDescendants
        self.createdAt = createdAt
    }
}

public struct UserPathPolicy: Codable, Hashable, Sendable {
    public static let empty = UserPathPolicy(rules: [])

    public let rules: [UserPathRule]

    public init(rules: [UserPathRule]) {
        self.rules = Self.deduplicated(rules)
    }

    public func rules(kind: UserPathPolicyKind) -> [UserPathRule] {
        rules.filter { $0.kind == kind }
    }

    public func matchingRule(for path: String, kind: UserPathPolicyKind? = nil) -> UserPathRule? {
        let standardized = Self.standardizedPath(path)
        return rules
            .filter { rule in
                if let kind, rule.kind != kind {
                    return false
                }
                return Self.path(standardized, matches: rule)
            }
            .sorted { lhs, rhs in
                lhs.path.count > rhs.path.count
            }
            .first
    }

    public func adding(path: String, kind: UserPathPolicyKind, reason: String? = nil) -> UserPathPolicy {
        let rule = UserPathRule(kind: kind, path: path, reason: reason)
        let filtered = rules.filter { !($0.kind == kind && $0.path == rule.path) }
        return UserPathPolicy(rules: filtered + [rule])
    }

    public func removing(path: String, kind: UserPathPolicyKind? = nil) -> UserPathPolicy {
        let standardized = Self.standardizedPath(path)
        return UserPathPolicy(
            rules: rules.filter { rule in
                if let kind, rule.kind != kind {
                    return true
                }
                return rule.path != standardized
            }
        )
    }

    public static func standardizedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath.standardizedFileURLPath
    }

    private static func path(_ path: String, matches rule: UserPathRule) -> Bool {
        if path == rule.path {
            return true
        }
        guard rule.includeDescendants else {
            return false
        }
        let prefix = rule.path.hasSuffix("/") ? rule.path : rule.path + "/"
        return path.hasPrefix(prefix)
    }

    private static func deduplicated(_ rules: [UserPathRule]) -> [UserPathRule] {
        var seen = Set<String>()
        var output: [UserPathRule] = []
        for rule in rules {
            let key = "\(rule.kind.rawValue):\(rule.path)"
            guard seen.insert(key).inserted else {
                continue
            }
            output.append(rule)
        }
        return output.sorted { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.path < rhs.path
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }
}

public struct UserPathPolicyDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultNonClaims = [
        "Importing this file changes only Ryddi's local protections and exclusions.",
        "Importing this file does not delete files, execute cleanup, grant macOS permissions, or prove that paths still exist.",
        "Policy exports can contain private local paths and user-entered reasons; review before sharing."
    ]

    public let schemaVersion: Int
    public let id: String
    public let exportedAt: Date
    public let rules: [UserPathRule]
    public let nonClaims: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String = UUID().uuidString,
        exportedAt: Date = Date(),
        rules: [UserPathRule],
        nonClaims: [String] = Self.defaultNonClaims
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.exportedAt = exportedAt
        self.rules = UserPathPolicy(rules: rules).rules
        self.nonClaims = nonClaims
    }

    public var policy: UserPathPolicy {
        UserPathPolicy(rules: rules)
    }
}

public struct UserPathPolicyImportResult: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let policyPath: String
    public let mode: String
    public let importedRuleCount: Int
    public let finalRuleCount: Int
    public let policy: UserPathPolicy
    public let nonClaims: [String]

    public init(
        sourcePath: String,
        policyPath: String,
        mode: String,
        importedRuleCount: Int,
        finalRuleCount: Int,
        policy: UserPathPolicy,
        nonClaims: [String]
    ) {
        self.sourcePath = sourcePath
        self.policyPath = policyPath
        self.mode = mode
        self.importedRuleCount = importedRuleCount
        self.finalRuleCount = finalRuleCount
        self.policy = policy
        self.nonClaims = nonClaims
    }
}

public enum UserPathPolicyDocumentError: LocalizedError {
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported user path policy document schema version: \(version)"
        }
    }
}

public final class UserPathPolicyStore: @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL = UserPathPolicyStore.defaultRoot(), fileManager: FileManager = .default) {
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
        root.appendingPathComponent("user-path-policy.json")
    }

    public func load() -> UserPathPolicy {
        guard let data = try? Data(contentsOf: policyURL),
              let policy = try? decoder.decode(UserPathPolicy.self, from: data) else {
            return .empty
        }
        return policy
    }

    public func exportDocument(exportedAt: Date = Date()) -> UserPathPolicyDocument {
        UserPathPolicyDocument(exportedAt: exportedAt, rules: load().rules)
    }

    @discardableResult
    public func writeExport(to url: URL, exportedAt: Date = Date()) throws -> URL {
        try writeExport(exportDocument(exportedAt: exportedAt), to: url)
    }

    @discardableResult
    public func writeExport(_ document: UserPathPolicyDocument, to url: URL) throws -> URL {
        try SafeFileOutput.write(encoder.encode(document), to: url)
    }

    @discardableResult
    public func importDocument(from url: URL, merge: Bool = true) throws -> UserPathPolicyImportResult {
        let data = try Data(contentsOf: url)
        let document = try decodePolicyDocument(from: data)
        guard document.schemaVersion == UserPathPolicyDocument.currentSchemaVersion else {
            throw UserPathPolicyDocumentError.unsupportedSchemaVersion(document.schemaVersion)
        }

        let imported = document.policy
        let finalPolicy: UserPathPolicy
        if merge {
            let importedKeys = Set(imported.rules.map(Self.ruleKey))
            let retained = load().rules.filter { !importedKeys.contains(Self.ruleKey($0)) }
            finalPolicy = UserPathPolicy(rules: retained + imported.rules)
        } else {
            finalPolicy = imported
        }
        try save(finalPolicy)
        return UserPathPolicyImportResult(
            sourcePath: url.standardizedFileURL.path,
            policyPath: policyURL.path,
            mode: merge ? "merge" : "replace",
            importedRuleCount: imported.rules.count,
            finalRuleCount: finalPolicy.rules.count,
            policy: finalPolicy,
            nonClaims: document.nonClaims
        )
    }

    @discardableResult
    public func save(_ policy: UserPathPolicy) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(policy).write(to: policyURL, options: .atomic)
        return policyURL
    }

    @discardableResult
    public func add(path: String, kind: UserPathPolicyKind, reason: String? = nil) throws -> UserPathPolicy {
        let policy = load().adding(path: path, kind: kind, reason: reason)
        try save(policy)
        return policy
    }

    @discardableResult
    public func remove(path: String, kind: UserPathPolicyKind? = nil) throws -> UserPathPolicy {
        let policy = load().removing(path: path, kind: kind)
        try save(policy)
        return policy
    }

    private func decodePolicyDocument(from data: Data) throws -> UserPathPolicyDocument {
        do {
            return try decoder.decode(UserPathPolicyDocument.self, from: data)
        } catch {
            let policy = try decoder.decode(UserPathPolicy.self, from: data)
            return UserPathPolicyDocument(rules: policy.rules)
        }
    }

    private static func ruleKey(_ rule: UserPathRule) -> String {
        "\(rule.kind.rawValue):\(rule.path)"
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
