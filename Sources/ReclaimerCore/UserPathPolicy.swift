import Darwin
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

    public static func failClosed(reason: String) -> UserPathPolicy {
        UserPathPolicy(rules: [
            UserPathRule(
                id: "ryddi.user-policy.fail-closed",
                kind: .protect,
                path: "/",
                reason: reason,
                includeDescendants: true,
                createdAt: Date(timeIntervalSince1970: 0)
            )
        ])
    }

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

public enum UserPathPolicyLoadState: String, Codable, CaseIterable, Hashable, Sendable {
    case missing
    case loaded
    case loadedWithInsecurePermissions
    case unreadable
    case corrupt
    case unsafeStorage
}

public struct UserPathPolicyLoadResult: Hashable, Sendable {
    public let state: UserPathPolicyLoadState
    public let policy: UserPathPolicy
    public let detail: String

    public init(state: UserPathPolicyLoadState, policy: UserPathPolicy, detail: String) {
        self.state = state
        self.policy = policy
        self.detail = detail
    }

    public var enforcementPolicy: UserPathPolicy {
        switch state {
        case .missing, .loaded, .loadedWithInsecurePermissions:
            policy
        case .unreadable, .corrupt, .unsafeStorage:
            .failClosed(reason: detail)
        }
    }

    public var canMutate: Bool {
        switch state {
        case .missing, .loaded, .loadedWithInsecurePermissions:
            true
        case .unreadable, .corrupt, .unsafeStorage:
            false
        }
    }
}

public enum UserPathPolicyStoreError: Error, LocalizedError, Equatable {
    case currentPolicyUnavailable(UserPathPolicyLoadState)
    case unsafeStorage(String)
    case writeFailed(String)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .currentPolicyUnavailable(let state):
            "The current path policy is \(state.rawValue) and cannot be changed safely. Review or restore the policy file first."
        case .unsafeStorage(let reason):
            "The path policy storage location is unsafe: \(reason)"
        case .writeFailed(let reason):
            "The path policy could not be written safely: \(reason)"
        case .verificationFailed:
            "The path policy write could not be verified by an exact readback."
        }
    }
}

public protocol UserPathPolicyLoading: Sendable {
    func loadResult() -> UserPathPolicyLoadResult
    func withLockedLoadResult<Result>(
        _ operation: (UserPathPolicyLoadResult) throws -> Result
    ) throws -> Result
}

public final class UserPathPolicyStore: UserPathPolicyLoading, @unchecked Sendable {
    public static let maximumPolicyBytes: Int64 = 1_048_576

    private static let policyFileName = "user-path-policy.json"
    private static let mutationLockFileName = ".user-path-policy.lock"
    private static let processMutationLock = NSLock()
    private let root: URL
    private let fileManager: FileManager

    public init(root: URL = UserPathPolicyStore.defaultRoot(), fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_CONFIG_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ryddi/Config", isDirectory: true)
    }

    public var policyURL: URL {
        root.appendingPathComponent(Self.policyFileName)
    }

    public func load() -> UserPathPolicy {
        loadResult().enforcementPolicy
    }

    public func loadResult() -> UserPathPolicyLoadResult {
        var rootMetadata = Darwin.stat()
        let rootStatus = root.path.withCString { Darwin.lstat($0, &rootMetadata) }
        if rootStatus != 0 {
            if errno == ENOENT {
                return UserPathPolicyLoadResult(
                    state: .missing,
                    policy: .empty,
                    detail: "No saved path policy exists yet."
                )
            }
            return UserPathPolicyLoadResult(
                state: .unreadable,
                policy: .empty,
                detail: "The path policy directory could not be inspected."
            )
        }
        guard Self.isDirectory(rootMetadata), !Self.isSymbolicLink(rootMetadata) else {
            return UserPathPolicyLoadResult(
                state: .unsafeStorage,
                policy: .empty,
                detail: "The path policy root is not an ordinary directory."
            )
        }

        let rootDescriptor = root.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard rootDescriptor >= 0 else {
            return UserPathPolicyLoadResult(
                state: .unreadable,
                policy: .empty,
                detail: "The path policy directory could not be opened."
            )
        }
        defer { Darwin.close(rootDescriptor) }

        var openedRootMetadata = Darwin.stat()
        guard Darwin.fstat(rootDescriptor, &openedRootMetadata) == 0,
              Self.isDirectory(openedRootMetadata),
              Self.sameIdentity(rootMetadata, openedRootMetadata) else {
            return UserPathPolicyLoadResult(
                state: .unsafeStorage,
                policy: .empty,
                detail: "The path policy directory changed while it was being opened."
            )
        }

        switch readPolicy(from: rootDescriptor) {
        case .missing:
            return UserPathPolicyLoadResult(
                state: .missing,
                policy: .empty,
                detail: "No saved path policy exists yet."
            )
        case .failure(let state, let detail):
            return UserPathPolicyLoadResult(state: state, policy: .empty, detail: detail)
        case .success(let policy, _, let fileMode):
            let rootMode = UInt32(openedRootMetadata.st_mode & mode_t(0o777))
            let state: UserPathPolicyLoadState = rootMode == 0o700 && fileMode == 0o600
                ? .loaded
                : .loadedWithInsecurePermissions
            let detail = state == .loaded
                ? "The saved path policy was loaded and verified."
                : "The saved path policy loaded, but its directory or file permissions are broader than 0700/0600. The next save will repair them."
            return UserPathPolicyLoadResult(state: state, policy: policy, detail: detail)
        }
    }

    public func withLockedLoadResult<Result>(
        _ operation: (UserPathPolicyLoadResult) throws -> Result
    ) throws -> Result {
        try withExclusiveMutation { _ in
            try operation(loadResult())
        }
    }

    public func exportDocument(exportedAt: Date = Date()) throws -> UserPathPolicyDocument {
        UserPathPolicyDocument(exportedAt: exportedAt, rules: try policyForMutation().rules)
    }

    @discardableResult
    public func writeExport(to url: URL, exportedAt: Date = Date()) throws -> URL {
        try writeExport(try exportDocument(exportedAt: exportedAt), to: url)
    }

    @discardableResult
    public func writeExport(_ document: UserPathPolicyDocument, to url: URL) throws -> URL {
        try SafeFileOutput.write(Self.makeEncoder().encode(document), to: url)
    }

    @discardableResult
    public func importDocument(from url: URL, merge: Bool = true) throws -> UserPathPolicyImportResult {
        let data = try Self.readBoundedRegularFile(at: url)
        let document = try decodePolicyDocument(from: data)
        guard document.schemaVersion == UserPathPolicyDocument.currentSchemaVersion else {
            throw UserPathPolicyDocumentError.unsupportedSchemaVersion(document.schemaVersion)
        }

        let imported = document.policy
        let finalPolicy = try withExclusiveMutation { rootDescriptor in
            let current = try policyForMutation(from: rootDescriptor)
            let policy: UserPathPolicy
            if merge {
                let importedKeys = Set(imported.rules.map(Self.ruleKey))
                let retained = current.rules.filter { !importedKeys.contains(Self.ruleKey($0)) }
                policy = UserPathPolicy(rules: retained + imported.rules)
            } else {
                policy = imported
            }
            try write(policy, rootDescriptor: rootDescriptor)
            return policy
        }
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
        try withExclusiveMutation { rootDescriptor in
            _ = try policyForMutation(from: rootDescriptor)
            try write(policy, rootDescriptor: rootDescriptor)
        }
        return policyURL
    }

    @discardableResult
    public func add(path: String, kind: UserPathPolicyKind, reason: String? = nil) throws -> UserPathPolicy {
        try withExclusiveMutation { rootDescriptor in
            let policy = try policyForMutation(from: rootDescriptor)
                .adding(path: path, kind: kind, reason: reason)
            try write(policy, rootDescriptor: rootDescriptor)
            return policy
        }
    }

    @discardableResult
    public func remove(path: String, kind: UserPathPolicyKind? = nil) throws -> UserPathPolicy {
        try withExclusiveMutation { rootDescriptor in
            let policy = try policyForMutation(from: rootDescriptor).removing(path: path, kind: kind)
            try write(policy, rootDescriptor: rootDescriptor)
            return policy
        }
    }

    private func decodePolicyDocument(from data: Data) throws -> UserPathPolicyDocument {
        do {
            return try Self.makeDecoder().decode(UserPathPolicyDocument.self, from: data)
        } catch {
            let policy = try Self.makeDecoder().decode(UserPathPolicy.self, from: data)
            return UserPathPolicyDocument(rules: policy.rules)
        }
    }

    private static func ruleKey(_ rule: UserPathRule) -> String {
        "\(rule.kind.rawValue):\(rule.path)"
    }

    private enum PolicyReadResult {
        case missing
        case success(UserPathPolicy, data: Data, fileMode: UInt32)
        case failure(UserPathPolicyLoadState, String)
    }

    private func policyForMutation() throws -> UserPathPolicy {
        let result = loadResult()
        guard result.canMutate else {
            throw UserPathPolicyStoreError.currentPolicyUnavailable(result.state)
        }
        return result.policy
    }

    private func policyForMutation(from rootDescriptor: Int32) throws -> UserPathPolicy {
        switch readPolicy(from: rootDescriptor) {
        case .missing:
            return .empty
        case .success(let policy, _, _):
            return policy
        case .failure(let state, _):
            throw UserPathPolicyStoreError.currentPolicyUnavailable(state)
        }
    }

    private func write(_ policy: UserPathPolicy, rootDescriptor: Int32) throws {
        let data = try Self.makeEncoder().encode(policy)
        guard data.count <= Self.maximumPolicyBytes else {
            throw UserPathPolicyStoreError.writeFailed("the encoded policy exceeds the 1 MiB limit")
        }
        try writeAtomically(data, rootDescriptor: rootDescriptor)
    }

    private func withExclusiveMutation<T>(_ operation: (Int32) throws -> T) throws -> T {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }

        let rootDescriptor = try privateRootDescriptor()
        defer { Darwin.close(rootDescriptor) }
        let lockDescriptor = try openMutationLock(rootDescriptor: rootDescriptor)
        defer { Darwin.close(lockDescriptor) }

        while Self.setAdvisoryLock(lockDescriptor, type: Int16(F_WRLCK), command: F_SETLKW) != 0 {
            guard errno == EINTR else {
                throw UserPathPolicyStoreError.unsafeStorage("the mutation lock could not be acquired")
            }
        }
        defer { _ = Self.setAdvisoryLock(lockDescriptor, type: Int16(F_UNLCK), command: F_SETLK) }

        var openedLockMetadata = Darwin.stat()
        var currentLockMetadata = Darwin.stat()
        guard Darwin.fstat(lockDescriptor, &openedLockMetadata) == 0,
              Self.mutationLockFileName.withCString({
                  Darwin.fstatat(rootDescriptor, $0, &currentLockMetadata, AT_SYMLINK_NOFOLLOW)
              }) == 0,
              Self.isRegularFile(currentLockMetadata),
              !Self.isSymbolicLink(currentLockMetadata),
              Self.sameIdentity(openedLockMetadata, currentLockMetadata) else {
            throw UserPathPolicyStoreError.unsafeStorage("the mutation lock changed while it was being acquired")
        }

        return try operation(rootDescriptor)
    }

    private func openMutationLock(rootDescriptor: Int32) throws -> Int32 {
        var existing = Darwin.stat()
        let existingStatus = Self.mutationLockFileName.withCString {
            Darwin.fstatat(rootDescriptor, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        if existingStatus == 0 {
            guard Self.isRegularFile(existing), !Self.isSymbolicLink(existing) else {
                throw UserPathPolicyStoreError.unsafeStorage("the mutation lock is not an ordinary file")
            }
        } else if errno != ENOENT {
            throw UserPathPolicyStoreError.unsafeStorage("the mutation lock could not be inspected")
        }

        let descriptor = Self.mutationLockFileName.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
                0o600
            )
        }
        guard descriptor >= 0 else {
            throw UserPathPolicyStoreError.unsafeStorage(
                "the mutation lock could not be opened safely: \(Self.errnoDescription())"
            )
        }

        var opened = Darwin.stat()
        guard Darwin.fstat(descriptor, &opened) == 0,
              Self.isRegularFile(opened),
              !Self.isSymbolicLink(opened),
              Darwin.fchmod(descriptor, 0o600) == 0 else {
            Darwin.close(descriptor)
            throw UserPathPolicyStoreError.unsafeStorage("the mutation lock could not be verified")
        }
        return descriptor
    }

    private func privateRootDescriptor() throws -> Int32 {
        try validateMutationRootPath()

        var metadata = Darwin.stat()
        let status = root.path.withCString { Darwin.lstat($0, &metadata) }
        if status != 0 {
            guard errno == ENOENT else {
                throw UserPathPolicyStoreError.unsafeStorage("the root could not be inspected")
            }
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
            )
            guard root.path.withCString({ Darwin.lstat($0, &metadata) }) == 0 else {
                throw UserPathPolicyStoreError.unsafeStorage("the created root could not be inspected")
            }
        } else {
            guard Self.isDirectory(metadata), !Self.isSymbolicLink(metadata) else {
                throw UserPathPolicyStoreError.unsafeStorage("the root is not an ordinary directory")
            }
        }

        let descriptor = root.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw UserPathPolicyStoreError.unsafeStorage(Self.errnoDescription())
        }
        var openedMetadata = Darwin.stat()
        guard Darwin.fstat(descriptor, &openedMetadata) == 0,
              Self.isDirectory(openedMetadata),
              openedMetadata.st_uid == Darwin.geteuid(),
              Self.sameIdentity(metadata, openedMetadata) else {
            Darwin.close(descriptor)
            throw UserPathPolicyStoreError.unsafeStorage("the root changed while it was being opened")
        }
        guard Darwin.fchmod(descriptor, 0o700) == 0 else {
            Darwin.close(descriptor)
            throw UserPathPolicyStoreError.writeFailed(Self.errnoDescription())
        }
        return descriptor
    }

    private func validateMutationRootPath() throws {
        let path = root.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let protectedRoots: Set<String> = [
            "/",
            "/Applications",
            "/Library",
            "/System",
            "/System/Volumes/Data",
            "/Users",
            "/Volumes",
            "/private",
            "/private/tmp",
            "/private/var",
            "/tmp",
            "/var",
            home
        ]
        guard !protectedRoots.contains(path) else {
            throw UserPathPolicyStoreError.unsafeStorage(
                "a protected directory cannot be used as the path policy root"
            )
        }
    }

    private func writeAtomically(
        _ data: Data,
        rootDescriptor: Int32
    ) throws {
        var existing = Darwin.stat()
        let existingStatus = Self.policyFileName.withCString {
            Darwin.fstatat(rootDescriptor, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        if existingStatus == 0 {
            guard Self.isRegularFile(existing), !Self.isSymbolicLink(existing) else {
                throw UserPathPolicyStoreError.unsafeStorage("the policy file is not an ordinary file")
            }
        } else if errno != ENOENT {
            throw UserPathPolicyStoreError.unsafeStorage("the policy file could not be inspected")
        }

        let temporaryName = ".user-path-policy.\(UUID().uuidString).tmp"
        let descriptor = temporaryName.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                0o600
            )
        }
        guard descriptor >= 0 else {
            throw UserPathPolicyStoreError.writeFailed(Self.errnoDescription())
        }
        var shouldUnlink = true
        defer {
            Darwin.close(descriptor)
            if shouldUnlink {
                _ = temporaryName.withCString { Darwin.unlinkat(rootDescriptor, $0, 0) }
            }
        }

        guard Darwin.fchmod(descriptor, 0o600) == 0 else {
            throw UserPathPolicyStoreError.writeFailed(Self.errnoDescription())
        }
        try Self.writeAll(data, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else {
            throw UserPathPolicyStoreError.writeFailed(Self.errnoDescription())
        }
        let renameStatus = temporaryName.withCString { temporaryPointer in
            Self.policyFileName.withCString { policyPointer in
                Darwin.renameat(rootDescriptor, temporaryPointer, rootDescriptor, policyPointer)
            }
        }
        guard renameStatus == 0 else {
            throw UserPathPolicyStoreError.writeFailed(Self.errnoDescription())
        }
        shouldUnlink = false
        guard Darwin.fsync(rootDescriptor) == 0 else {
            throw UserPathPolicyStoreError.writeFailed(Self.errnoDescription())
        }

        guard case .success(_, let readbackData, let fileMode) = readPolicy(from: rootDescriptor),
              fileMode == 0o600,
              readbackData == data else {
            throw UserPathPolicyStoreError.verificationFailed
        }
    }

    private func readPolicy(from rootDescriptor: Int32) -> PolicyReadResult {
        let descriptor = Self.policyFileName.withCString {
            Darwin.openat(rootDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            switch errno {
            case ENOENT:
                return .missing
            case EACCES, EPERM:
                return .failure(.unreadable, "The path policy file is not readable.")
            default:
                return .failure(.unsafeStorage, "The path policy file could not be opened safely.")
            }
        }
        defer { Darwin.close(descriptor) }

        var before = Darwin.stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              Self.isRegularFile(before),
              !Self.isSymbolicLink(before) else {
            return .failure(.unsafeStorage, "The path policy file is not an ordinary file.")
        }
        guard before.st_size >= 0, Int64(before.st_size) <= Self.maximumPolicyBytes else {
            return .failure(.corrupt, "The path policy file exceeds the bounded size limit.")
        }

        let expectedBytes = Int(before.st_size)
        var data = Data(count: expectedBytes)
        let readSucceeded = data.withUnsafeMutableBytes { buffer -> Bool in
            guard expectedBytes > 0, let base = buffer.baseAddress else {
                return expectedBytes == 0
            }
            var offset = 0
            while offset < expectedBytes {
                let count = Darwin.read(descriptor, base.advanced(by: offset), expectedBytes - offset)
                if count > 0 {
                    offset += count
                    continue
                }
                if count < 0, errno == EINTR {
                    continue
                }
                return false
            }
            return true
        }
        guard readSucceeded else {
            return .failure(.unreadable, "The path policy file could not be read completely.")
        }

        var after = Darwin.stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              Self.sameIdentityAndMetadata(before, after) else {
            return .failure(.unsafeStorage, "The path policy file changed while it was being read.")
        }
        guard let policy = try? Self.makeDecoder().decode(UserPathPolicy.self, from: data) else {
            return .failure(.corrupt, "The path policy file contains invalid JSON or an unsupported policy shape.")
        }
        return .success(policy, data: data, fileMode: UInt32(after.st_mode & mode_t(0o777)))
    }

    private static func readBoundedRegularFile(at url: URL) throws -> Data {
        let path = url.standardizedFileURL.path
        var pathMetadata = Darwin.stat()
        guard path.withCString({ Darwin.lstat($0, &pathMetadata) }) == 0 else {
            throw UserPathPolicyStoreError.unsafeStorage("the import source could not be inspected")
        }
        guard Self.isRegularFile(pathMetadata), !Self.isSymbolicLink(pathMetadata) else {
            throw UserPathPolicyStoreError.unsafeStorage("the import source is not an ordinary file")
        }

        let descriptor = path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard descriptor >= 0 else {
            throw UserPathPolicyStoreError.unsafeStorage("the import source could not be opened safely")
        }
        defer { Darwin.close(descriptor) }

        var before = Darwin.stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              Self.isRegularFile(before),
              Self.sameIdentity(pathMetadata, before) else {
            throw UserPathPolicyStoreError.unsafeStorage("the import source changed while it was being opened")
        }
        guard before.st_size >= 0, Int64(before.st_size) <= maximumPolicyBytes else {
            throw UserPathPolicyStoreError.unsafeStorage("the import source exceeds the bounded size limit")
        }

        let expectedBytes = Int(before.st_size)
        var data = Data(count: expectedBytes)
        let readSucceeded = data.withUnsafeMutableBytes { buffer -> Bool in
            guard expectedBytes > 0, let base = buffer.baseAddress else {
                return expectedBytes == 0
            }
            var offset = 0
            while offset < expectedBytes {
                let count = Darwin.read(descriptor, base.advanced(by: offset), expectedBytes - offset)
                if count > 0 {
                    offset += count
                    continue
                }
                if count < 0, errno == EINTR {
                    continue
                }
                return false
            }
            return true
        }
        guard readSucceeded else {
            throw UserPathPolicyStoreError.unsafeStorage("the import source could not be read completely")
        }

        var after = Darwin.stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              Self.sameIdentityAndMetadata(before, after) else {
            throw UserPathPolicyStoreError.unsafeStorage("the import source changed while it was being read")
        }
        return data
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count > 0 {
                    offset += count
                    continue
                }
                if count < 0, errno == EINTR {
                    continue
                }
                throw UserPathPolicyStoreError.writeFailed(Self.errnoDescription())
            }
        }
    }

    private static func setAdvisoryLock(_ descriptor: Int32, type: Int16, command: Int32) -> Int32 {
        var lock = Darwin.flock()
        lock.l_start = 0
        lock.l_len = 0
        lock.l_pid = 0
        lock.l_type = type
        lock.l_whence = Int16(SEEK_SET)
        return Darwin.fcntl(descriptor, command, &lock)
    }

    private static func isDirectory(_ metadata: Darwin.stat) -> Bool {
        metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    }

    private static func isRegularFile(_ metadata: Darwin.stat) -> Bool {
        metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    private static func isSymbolicLink(_ metadata: Darwin.stat) -> Bool {
        metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK)
    }

    private static func sameIdentityAndMetadata(_ lhs: Darwin.stat, _ rhs: Darwin.stat) -> Bool {
        sameIdentity(lhs, rhs)
            && lhs.st_mode == rhs.st_mode
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
    }

    private static func sameIdentity(_ lhs: Darwin.stat, _ rhs: Darwin.stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private static func errnoDescription() -> String {
        String(cString: Darwin.strerror(errno))
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
