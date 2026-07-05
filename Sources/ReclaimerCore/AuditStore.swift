import Foundation

public final class AuditStore: @unchecked Sendable {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL = AuditStore.defaultRoot()) {
        self.root = root
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_AUDIT_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Ryddi/Audit")
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

    public func save(nativeToolReport: NativeToolReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("native-tool-\(nativeToolReport.id).json")
        try encoder.encode(nativeToolReport).write(to: url, options: .atomic)
        return url
    }

    public func save(containerInventoryReport: ContainerInventoryReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("container-inventory-\(containerInventoryReport.id).json")
        try encoder.encode(containerInventoryReport).write(to: url, options: .atomic)
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

    public func recentNativeToolReports(limit: Int = 20) -> [NativeToolReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("native-tool-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(NativeToolReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentContainerInventoryReports(limit: Int = 20) -> [ContainerInventoryReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("container-inventory-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(ContainerInventoryReport.self, from: Data(contentsOf: $0)) }
    }
}
