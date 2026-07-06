import Foundation

public enum DiskPressureLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case healthy
    case warning
    case critical
    case unknown

    public var label: String {
        switch self {
        case .healthy: "Healthy"
        case .warning: "Low space"
        case .critical: "Critical"
        case .unknown: "Unknown"
        }
    }
}

public struct DiskStatusThresholds: Codable, Hashable, Sendable {
    public let warningFreeBytes: Int64
    public let criticalFreeBytes: Int64
    public let warningFreeFraction: Double
    public let criticalFreeFraction: Double

    public init(
        warningFreeBytes: Int64 = 50 * 1024 * 1024 * 1024,
        criticalFreeBytes: Int64 = 20 * 1024 * 1024 * 1024,
        warningFreeFraction: Double = 0.15,
        criticalFreeFraction: Double = 0.07
    ) {
        self.warningFreeBytes = warningFreeBytes
        self.criticalFreeBytes = criticalFreeBytes
        self.warningFreeFraction = warningFreeFraction
        self.criticalFreeFraction = criticalFreeFraction
    }
}

public struct DiskStatusSnapshot: Codable, Hashable, Sendable {
    public let createdAt: Date
    public let path: String
    public let volumeName: String?
    public let totalBytes: Int64?
    public let freeBytes: Int64?
    public let importantFreeBytes: Int64?
    public let availableBytes: Int64?
    public let pressure: DiskPressureLevel
    public let notes: [String]

    public init(
        createdAt: Date = Date(),
        path: String,
        volumeName: String? = nil,
        totalBytes: Int64?,
        freeBytes: Int64?,
        importantFreeBytes: Int64?,
        availableBytes: Int64?,
        pressure: DiskPressureLevel,
        notes: [String]
    ) {
        self.createdAt = createdAt
        self.path = path
        self.volumeName = volumeName
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.importantFreeBytes = importantFreeBytes
        self.availableBytes = availableBytes
        self.pressure = pressure
        self.notes = notes
    }

    public var displayFreeBytes: Int64? {
        importantFreeBytes ?? availableBytes ?? freeBytes
    }

    public var freeFraction: Double? {
        guard let totalBytes, totalBytes > 0, let displayFreeBytes else { return nil }
        return Double(displayFreeBytes) / Double(totalBytes)
    }

    public var statusLine: String {
        guard let displayFreeBytes else {
            return "Disk status unavailable"
        }
        if let totalBytes, totalBytes > 0 {
            let percent = (Double(displayFreeBytes) / Double(totalBytes)) * 100
            return "\(ByteFormat.string(displayFreeBytes)) free (\(Int(percent.rounded()))%)"
        }
        return "\(ByteFormat.string(displayFreeBytes)) free"
    }
}

public final class DiskStatusReader: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func snapshot(
        for url: URL = URL(fileURLWithPath: "/System/Volumes/Data"),
        thresholds: DiskStatusThresholds = DiskStatusThresholds()
    ) -> DiskStatusSnapshot {
        let standardized = url.standardizedFileURL
        do {
            let values = try standardized.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let total = values.volumeTotalCapacity.map(Int64.init)
            let free = values.volumeAvailableCapacity.map(Int64.init)
            let important = values.volumeAvailableCapacityForImportantUsage
            let available = values.volumeAvailableCapacity.map(Int64.init)
            let pressure = Self.pressure(
                freeBytes: important ?? available ?? free,
                totalBytes: total,
                thresholds: thresholds
            )
            return DiskStatusSnapshot(
                path: standardized.path,
                volumeName: values.volumeName,
                totalBytes: total,
                freeBytes: free,
                importantFreeBytes: important,
                availableBytes: available,
                pressure: pressure,
                notes: notes(for: pressure)
            )
        } catch {
            return DiskStatusSnapshot(
                path: standardized.path,
                totalBytes: nil,
                freeBytes: nil,
                importantFreeBytes: nil,
                availableBytes: nil,
                pressure: .unknown,
                notes: ["Could not read disk status: \(error.localizedDescription)"]
            )
        }
    }

    public static func pressure(
        freeBytes: Int64?,
        totalBytes: Int64?,
        thresholds: DiskStatusThresholds = DiskStatusThresholds()
    ) -> DiskPressureLevel {
        guard let freeBytes, freeBytes >= 0 else { return .unknown }
        let fraction = totalBytes.flatMap { total -> Double? in
            guard total > 0 else { return nil }
            return Double(freeBytes) / Double(total)
        }
        if freeBytes <= thresholds.criticalFreeBytes || (fraction ?? 1) <= thresholds.criticalFreeFraction {
            return .critical
        }
        if freeBytes <= thresholds.warningFreeBytes || (fraction ?? 1) <= thresholds.warningFreeFraction {
            return .warning
        }
        return .healthy
    }

    private func notes(for pressure: DiskPressureLevel) -> [String] {
        switch pressure {
        case .healthy:
            return ["Free space is above Ryddi's default warning thresholds."]
        case .warning:
            return ["Free space is low. Run a report-first scan before removing anything."]
        case .critical:
            return ["Free space is critically low. Avoid long build loops until reclaim candidates are reviewed."]
        case .unknown:
            return ["Disk status could not be determined."]
        }
    }
}
