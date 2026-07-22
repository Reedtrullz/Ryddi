import Foundation

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
    public init(name: String, path: String, sizeBytes: Int64, bucket: Bucket, ruleTitle: String) {
        self.name = name; self.path = path; self.sizeBytes = sizeBytes; self.bucket = bucket; self.ruleTitle = ruleTitle
    }

    public var groupKey: String {
        if let at = name.firstIndex(of: "@") {
            return String(name[..<at])
        }
        return name
    }
}

public struct ScanItemGroup: Identifiable, Sendable {
    public let id = UUID()
    public let baseName: String
    public let items: [ScanItem]
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
