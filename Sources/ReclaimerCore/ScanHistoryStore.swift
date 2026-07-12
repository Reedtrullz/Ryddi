import Foundation

public final class ScanHistoryStore: @unchecked Sendable {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_SCAN_HISTORY_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Ryddi/ScanHistory")
    }

    public func save(overview: ScanOverview, keepLimit: Int = 30) throws -> URL {
        try save(snapshot: FindingAnalytics.snapshot(from: overview), keepLimit: keepLimit)
    }

    @discardableResult
    public func save(snapshot: ScanSnapshot, keepLimit: Int = 30) throws -> URL {
        _ = keepLimit
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("scan-\(timestamp(snapshot.createdAt))-\(snapshot.id).json")
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        return url
    }

    public func recent(limit: Int = 10) -> [ScanSnapshot] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("scan-") && $0.pathExtension == "json" }
            .compactMap { url -> (URL, ScanSnapshot)? in
                guard let data = try? Data(contentsOf: url),
                      let snapshot = try? decoder.decode(ScanSnapshot.self, from: data) else {
                    return nil
                }
                return (url, snapshot)
            }
            .sorted { lhs, rhs in
                if lhs.1.createdAt == rhs.1.createdAt {
                    return lhs.0.lastPathComponent > rhs.0.lastPathComponent
                }
                return lhs.1.createdAt > rhs.1.createdAt
            }
            .prefix(limit)
            .map(\.1)
    }

    public func snapshot(id: String) -> ScanSnapshot? {
        recent(limit: Int.max).first { $0.id == id }
    }

    public func latestGrowthDeltas(group: GrowthGroup = .category, limit: Int = 12) -> [BucketGrowthDelta] {
        let snapshots = recent(limit: 2)
        guard snapshots.count == 2 else { return [] }
        return Array(
            FindingAnalytics.growthDeltas(previous: snapshots[1], current: snapshots[0], group: group)
                .prefix(limit)
        )
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}
