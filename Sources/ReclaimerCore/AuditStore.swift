import Foundation

public final class AuditStore: @unchecked Sendable {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Ryddi/Audit")) {
        self.root = root
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func save(plan: ReclaimPlan) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("plan-\(plan.id).json")
        try encoder.encode(plan).write(to: url, options: .atomic)
        return url
    }

    public func save(receipt: ExecutionReceipt) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("receipt-\(receipt.id).json")
        try encoder.encode(receipt).write(to: url, options: .atomic)
        return url
    }

    public func recentReceipts(limit: Int = 20) -> [ExecutionReceipt] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("receipt-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(ExecutionReceipt.self, from: Data(contentsOf: $0)) }
    }

    public func recentPlans(limit: Int = 20) -> [ReclaimPlan] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("plan-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(ReclaimPlan.self, from: Data(contentsOf: $0)) }
    }
}
