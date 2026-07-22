import Foundation
import Darwin

public struct FileIdentity: Codable, Hashable, Sendable {
    public let canonicalPath: String
    public let device: UInt64
    public let inode: UInt64
    public let isDirectory: Bool
    public let isSymbolicLink: Bool

    public static func capture(path: String) -> FileIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let kind = info.st_mode & S_IFMT
        let symbolicLink = kind == S_IFLNK
        let directory = kind == S_IFDIR
        let canonical = symbolicLink
            ? (path as NSString).standardizingPath
            : canonicalizedPath(path)
        return FileIdentity(
            canonicalPath: canonical,
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            isDirectory: directory,
            isSymbolicLink: symbolicLink
        )
    }

    public func matchesCurrent(path: String) -> Bool {
        guard let current = Self.capture(path: path) else { return false }
        return current == self
    }
}

public enum SafetyClass: String, Codable, Hashable, Sendable {
    case autoSafe, safeAfterCondition, preserveByDefault, reviewRequired, neverTouch

    public var riskRank: Int {
        switch self {
        case .autoSafe: 0
        case .safeAfterCondition: 1
        case .reviewRequired: 2
        case .preserveByDefault: 3
        case .neverTouch: 4
        }
    }
}

public enum ActionKind: String, Codable, Hashable, Sendable {
    case trash, deleteCache, compress, reportOnly, openGuidance, nativeToolCommand
}

public enum Bucket: String, CaseIterable, Sendable {
    case safe = "Safe to Clean"
    case review = "Review First"
    case blocked = "Protected"

    var color: String {
        switch self { case .safe: "green"; case .review: "yellow"; case .blocked: "red" }
    }
    var icon: String {
        switch self { case .safe: "checkmark.circle.fill"; case .review: "eye.circle.fill"; case .blocked: "lock.circle.fill" }
    }
}

public struct ScanItem: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let bucket: Bucket
    public let ruleTitle: String
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let scanRoot: String
    public let identity: FileIdentity?
    public init(
        name: String,
        path: String,
        sizeBytes: Int64,
        bucket: Bucket,
        ruleTitle: String,
        safetyClass: SafetyClass = .reviewRequired,
        actionKind: ActionKind = .reportOnly,
        scanRoot: String? = nil,
        identity: FileIdentity? = nil
    ) {
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.bucket = bucket
        self.ruleTitle = ruleTitle
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.scanRoot = scanRoot ?? path
        self.identity = identity
    }

    public var groupKey: String {
        guard let at = name.lastIndex(of: "@"), at != name.startIndex else { return name }
        let suffix = name[name.index(after: at)...]
        let normalized = suffix.first == "v" ? suffix.dropFirst() : suffix[...]
        let versionCore = normalized.split(separator: "-", maxSplits: 1).first ?? ""
        let components = versionCore.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return name
        }
        return String(name[..<at])
    }
}

public struct ScanItemGroup: Identifiable, Sendable {
    public let baseName: String
    public let items: [ScanItem]
    public var id: String { baseName }
    public var totalSizeBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var count: Int { items.count }
    public init(baseName: String, items: [ScanItem]) {
        self.baseName = baseName; self.items = items
    }
}

public struct ScanRoot: Hashable, Sendable {
    public let name: String
    public let path: String
    public init(name: String, path: String) { self.name = name; self.path = path }
}
