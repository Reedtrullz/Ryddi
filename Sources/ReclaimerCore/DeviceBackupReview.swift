import Foundation

public enum DeviceBackupEncryptionState: String, Codable, CaseIterable, Hashable, Sendable {
    case encrypted
    case notEncrypted
    case unknown

    public var label: String {
        switch self {
        case .encrypted:
            return "Encrypted"
        case .notEncrypted:
            return "Not encrypted"
        case .unknown:
            return "Unknown"
        }
    }
}

public enum DeviceBackupMetadataState: String, Codable, CaseIterable, Hashable, Sendable {
    case parsed
    case missing
    case unreadable
    case invalid

    public var label: String {
        switch self {
        case .parsed:
            return "Parsed"
        case .missing:
            return "Missing"
        case .unreadable:
            return "Unreadable"
        case .invalid:
            return "Invalid"
        }
    }
}

public struct DeviceBackupItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let backupIdentifier: String
    public let displayName: String
    public let deviceName: String?
    public let productName: String?
    public let productType: String?
    public let lastBackupDate: Date?
    public let modificationDate: Date?
    public let ageDays: Int?
    public let encryptionState: DeviceBackupEncryptionState
    public let metadataState: DeviceBackupMetadataState
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let signals: [String]
    public let recommendation: String
    public let guidance: [String]

    public init(
        id: String = UUID().uuidString,
        path: String,
        backupIdentifier: String,
        displayName: String,
        deviceName: String? = nil,
        productName: String? = nil,
        productType: String? = nil,
        lastBackupDate: Date? = nil,
        modificationDate: Date? = nil,
        ageDays: Int? = nil,
        encryptionState: DeviceBackupEncryptionState,
        metadataState: DeviceBackupMetadataState,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        signals: [String],
        recommendation: String,
        guidance: [String]
    ) {
        self.id = id
        self.path = path
        self.backupIdentifier = backupIdentifier
        self.displayName = displayName
        self.deviceName = deviceName
        self.productName = productName
        self.productType = productType
        self.lastBackupDate = lastBackupDate
        self.modificationDate = modificationDate
        self.ageDays = ageDays
        self.encryptionState = encryptionState
        self.metadataState = metadataState
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.signals = signals
        self.recommendation = recommendation
        self.guidance = guidance
    }
}

public struct DeviceBackupSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let backupCount: Int
    public let allocatedSize: Int64

    public init(name: String, backupCount: Int, allocatedSize: Int64) {
        self.name = name
        self.backupCount = backupCount
        self.allocatedSize = allocatedSize
    }
}

public struct DeviceBackupReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let rootPath: String
    public let permissionState: PermissionState
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let itemCount: Int
    public let backupCount: Int
    public let displayedBackupCount: Int
    public let staleBackupBytes: Int64
    public let encryptedBackupBytes: Int64
    public let missingMetadataCount: Int
    public let encryptionSummaries: [DeviceBackupSummary]
    public let metadataSummaries: [DeviceBackupSummary]
    public let largestBackups: [DeviceBackupItem]
    public let notes: [String]
    public let guidance: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        rootPath: String,
        permissionState: PermissionState,
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        itemCount: Int,
        backupCount: Int,
        displayedBackupCount: Int,
        staleBackupBytes: Int64,
        encryptedBackupBytes: Int64,
        missingMetadataCount: Int,
        encryptionSummaries: [DeviceBackupSummary],
        metadataSummaries: [DeviceBackupSummary],
        largestBackups: [DeviceBackupItem],
        notes: [String],
        guidance: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rootPath = rootPath
        self.permissionState = permissionState
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.itemCount = itemCount
        self.backupCount = backupCount
        self.displayedBackupCount = displayedBackupCount
        self.staleBackupBytes = staleBackupBytes
        self.encryptedBackupBytes = encryptedBackupBytes
        self.missingMetadataCount = missingMetadataCount
        self.encryptionSummaries = encryptionSummaries
        self.metadataSummaries = metadataSummaries
        self.largestBackups = largestBackups
        self.notes = notes
        self.guidance = guidance
        self.nonClaims = nonClaims
    }
}

public struct DeviceBackupReviewOptions: Hashable, Sendable {
    public let root: URL
    public let limit: Int
    public let oldDays: Int
    public let measurementDepth: Int

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        root: URL? = nil,
        limit: Int = 50,
        oldDays: Int = 180,
        measurementDepth: Int = 12
    ) {
        let standardizedHome = home.standardizedFileURL
        self.root = (root ?? standardizedHome.appendingPathComponent("Library/Application Support/MobileSync/Backup")).standardizedFileURL
        self.limit = max(1, min(limit, 500))
        self.oldDays = max(1, min(oldDays, 3650))
        self.measurementDepth = max(0, min(measurementDepth, 32))
    }
}

public final class DeviceBackupReviewScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func review(
        options: DeviceBackupReviewOptions = DeviceBackupReviewOptions(),
        createdAt: Date = Date()
    ) -> DeviceBackupReviewReport {
        let root = options.root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return emptyReport(
                root: root,
                createdAt: createdAt,
                permissionState: .missing,
                note: "Device backup root does not exist at \(root.path)."
            )
        }
        guard isDirectory.boolValue else {
            return emptyReport(
                root: root,
                createdAt: createdAt,
                permissionState: .unknown,
                note: "Configured device backup root is not a directory: \(root.path)."
            )
        }
        guard fileManager.isReadableFile(atPath: root.path) else {
            return emptyReport(
                root: root,
                createdAt: createdAt,
                permissionState: .denied,
                note: "Device backup root is not readable with current permissions: \(root.path)."
            )
        }
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: deviceBackupResourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return emptyReport(
                root: root,
                createdAt: createdAt,
                permissionState: .denied,
                note: "Could not list device backup root at \(root.path)."
            )
        }

        let backups = children.map {
            item(
                for: $0,
                oldDays: options.oldDays,
                measurementDepth: options.measurementDepth,
                referenceDate: createdAt
            )
        }
            .sorted { lhs, rhs in
                if lhs.allocatedSize == rhs.allocatedSize {
                    return lhs.path < rhs.path
                }
                return lhs.allocatedSize > rhs.allocatedSize
            }

        let logical = backups.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = backups.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let measuredCount = backups.reduce(0) { $0 + max(1, $1.itemCount) }
        let staleBytes = backups
            .filter { ($0.ageDays ?? 0) >= options.oldDays }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let encryptedBytes = backups
            .filter { $0.encryptionState == .encrypted }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let missingMetadata = backups.filter { $0.metadataState != .parsed }.count

        return DeviceBackupReviewReport(
            createdAt: createdAt,
            rootPath: root.path,
            permissionState: .readable,
            totalLogicalSize: logical,
            totalAllocatedSize: allocated,
            itemCount: measuredCount,
            backupCount: backups.count,
            displayedBackupCount: min(backups.count, options.limit),
            staleBackupBytes: staleBytes,
            encryptedBackupBytes: encryptedBytes,
            missingMetadataCount: missingMetadata,
            encryptionSummaries: Self.encryptionSummaries(for: backups),
            metadataSummaries: Self.metadataSummaries(for: backups),
            largestBackups: Array(backups.prefix(options.limit)),
            notes: [
                "Measured immediate device backup folders under \(root.path).",
                "Old-backup threshold: \(options.oldDays) day(s).",
                "Backup metadata comes from each backup folder's Info.plist when readable."
            ],
            guidance: Self.guidance(rootPath: root.path),
            nonClaims: Self.nonClaims
        )
    }

    private func emptyReport(
        root: URL,
        createdAt: Date,
        permissionState: PermissionState,
        note: String
    ) -> DeviceBackupReviewReport {
        DeviceBackupReviewReport(
            createdAt: createdAt,
            rootPath: root.path,
            permissionState: permissionState,
            totalLogicalSize: 0,
            totalAllocatedSize: 0,
            itemCount: 0,
            backupCount: 0,
            displayedBackupCount: 0,
            staleBackupBytes: 0,
            encryptedBackupBytes: 0,
            missingMetadataCount: 0,
            encryptionSummaries: [],
            metadataSummaries: [],
            largestBackups: [],
            notes: [note],
            guidance: Self.guidance(rootPath: root.path),
            nonClaims: Self.nonClaims
        )
    }

    private func item(
        for url: URL,
        oldDays: Int,
        measurementDepth: Int,
        referenceDate: Date
    ) -> DeviceBackupItem {
        let values = try? url.resourceValues(forKeys: Set(deviceBackupResourceKeys))
        let metadata = readMetadata(for: url)
        let measurement = measure(url: url, maxDepth: measurementDepth)
        let modified = values?.contentModificationDate
        let referenceBackupDate = metadata.lastBackupDate ?? modified
        let ageDays = referenceBackupDate.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: referenceDate).day ?? 0) }
        let isOld = (ageDays ?? 0) >= oldDays
        let isSymbolicLink = values?.isSymbolicLink ?? false
        let displayName = metadata.displayName
            ?? metadata.deviceName
            ?? metadata.productName
            ?? "Device backup \(url.lastPathComponent.prefix(8))"
        let signals = Self.signals(
            isOld: isOld,
            encryptionState: metadata.encryptionState,
            metadataState: metadata.state,
            isSymbolicLink: isSymbolicLink
        )
        return DeviceBackupItem(
            path: url.path,
            backupIdentifier: url.lastPathComponent,
            displayName: String(displayName),
            deviceName: metadata.deviceName,
            productName: metadata.productName,
            productType: metadata.productType,
            lastBackupDate: metadata.lastBackupDate,
            modificationDate: modified,
            ageDays: ageDays,
            encryptionState: metadata.encryptionState,
            metadataState: metadata.state,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            itemCount: measurement.itemCount,
            isDirectory: values?.isDirectory ?? false,
            isSymbolicLink: isSymbolicLink,
            signals: signals,
            recommendation: Self.recommendation(
                isOld: isOld,
                metadataState: metadata.state,
                encryptionState: metadata.encryptionState,
                isSymbolicLink: isSymbolicLink
            ),
            guidance: Self.itemGuidance(
                isOld: isOld,
                metadataState: metadata.state,
                encryptionState: metadata.encryptionState,
                isSymbolicLink: isSymbolicLink
            )
        )
    }

    private func readMetadata(for backupURL: URL) -> DeviceBackupMetadata {
        let infoURL = backupURL.appendingPathComponent("Info.plist")
        guard fileManager.fileExists(atPath: infoURL.path) else {
            return DeviceBackupMetadata(state: .missing)
        }
        guard fileManager.isReadableFile(atPath: infoURL.path) else {
            return DeviceBackupMetadata(state: .unreadable)
        }
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dict = plist as? [String: Any]
        else {
            return DeviceBackupMetadata(state: .invalid)
        }

        return DeviceBackupMetadata(
            state: .parsed,
            displayName: firstString(in: dict, keys: ["Display Name", "Device Display Name", "Backup Display Name"]),
            deviceName: firstString(in: dict, keys: ["Device Name", "DeviceName"]),
            productName: firstString(in: dict, keys: ["Product Name", "ProductName"]),
            productType: firstString(in: dict, keys: ["Product Type", "ProductType"]),
            lastBackupDate: firstDate(in: dict, keys: ["Last Backup Date", "LastBackupDate"]),
            encryptionState: encryptionState(in: dict)
        )
    }

    private func measure(url: URL, maxDepth: Int) -> DeviceBackupMeasurement {
        guard let values = try? url.resourceValues(forKeys: Set(deviceBackupResourceKeys)) else {
            return DeviceBackupMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }
        if values.isSymbolicLink == true {
            return DeviceBackupMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return DeviceBackupMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1)
        }
        guard maxDepth > 0 else {
            return DeviceBackupMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: deviceBackupResourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return DeviceBackupMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        for case let child as URL in enumerator {
            let depth = max(0, child.pathComponents.count - url.pathComponents.count)
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(deviceBackupResourceKeys)) else { continue }
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
        return DeviceBackupMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: count)
    }

    private static func encryptionSummaries(for backups: [DeviceBackupItem]) -> [DeviceBackupSummary] {
        DeviceBackupEncryptionState.allCases.compactMap { state in
            let matches = backups.filter { $0.encryptionState == state }
            guard !matches.isEmpty else { return nil }
            return DeviceBackupSummary(
                name: state.label,
                backupCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func metadataSummaries(for backups: [DeviceBackupItem]) -> [DeviceBackupSummary] {
        DeviceBackupMetadataState.allCases.compactMap { state in
            let matches = backups.filter { $0.metadataState == state }
            guard !matches.isEmpty else { return nil }
            return DeviceBackupSummary(
                name: state.label,
                backupCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func signals(
        isOld: Bool,
        encryptionState: DeviceBackupEncryptionState,
        metadataState: DeviceBackupMetadataState,
        isSymbolicLink: Bool
    ) -> [String] {
        var result = ["device-backup"]
        if isOld {
            result.append("old-backup")
        }
        result.append(encryptionState.rawValue)
        if metadataState != .parsed {
            result.append("metadata-\(metadataState.rawValue)")
        }
        if isSymbolicLink {
            result.append("symlink-not-followed")
        }
        return result
    }

    private static func recommendation(
        isOld: Bool,
        metadataState: DeviceBackupMetadataState,
        encryptionState: DeviceBackupEncryptionState,
        isSymbolicLink: Bool
    ) -> String {
        if isSymbolicLink {
            return "Manual review only; symbolic links are not followed or cleaned by Device Backups Review."
        }
        if metadataState != .parsed {
            return "Review in Finder or Apple device backup management before any removal; metadata could not be verified."
        }
        if encryptionState == .encrypted {
            return "Preserve until you confirm you have another usable encrypted backup or no longer need this restore point."
        }
        if isOld {
            return "Review in Apple device backup management; remove only after confirming the device has a newer backup or is no longer needed."
        }
        return "Preserve by default; local device backups can be the only restore point for a device."
    }

    private static func itemGuidance(
        isOld: Bool,
        metadataState: DeviceBackupMetadataState,
        encryptionState: DeviceBackupEncryptionState,
        isSymbolicLink: Bool
    ) -> [String] {
        var guidance = [
            "Use Finder or Apple's storage/device backup UI to inspect and remove local device backups.",
            "Confirm iCloud or another current backup exists before removing a local backup."
        ]
        if isOld {
            guidance.append("Age is a review signal only; old backups can still be the only backup for an old device.")
        }
        if encryptionState == .encrypted {
            guidance.append("Encrypted backups may contain Health, Wi-Fi, and other protected restore data that an unencrypted backup may not replace.")
        }
        if metadataState != .parsed {
            guidance.append("Info.plist metadata was not parsed, so device identity and last-backup date may be unknown.")
        }
        if isSymbolicLink {
            guidance.append("Symbolic link was not followed while measuring.")
        }
        return guidance
    }

    private static func guidance(rootPath: String) -> [String] {
        [
            "Review \(rootPath) as Apple MobileSync device-backup storage, not as ordinary cache.",
            "Prefer Finder or Apple's storage/device backup management for deletion; avoid raw deletion unless you have made a deliberate backup decision.",
            "Check the device name, last backup date, and whether the backup is encrypted before removing anything.",
            "Keep at least one current, restorable backup for devices you still care about."
        ]
    }

    public static let nonClaims = [
        "Device Backups Review is report-only; it does not delete, move, Trash, prune, purge, or modify device backups.",
        "Ryddi cannot prove whether iCloud Backup, another Mac backup, or a newer local backup exists.",
        "Info.plist metadata can be missing, stale, unreadable, or incomplete; backup identity and dates may need Finder confirmation.",
        "Device backup size is not promised immediate free-space recovery because APFS snapshots, hard links, clones, and purgeable storage can affect accounting."
    ]
}

private struct DeviceBackupMetadata: Hashable {
    let state: DeviceBackupMetadataState
    let displayName: String?
    let deviceName: String?
    let productName: String?
    let productType: String?
    let lastBackupDate: Date?
    let encryptionState: DeviceBackupEncryptionState

    init(
        state: DeviceBackupMetadataState,
        displayName: String? = nil,
        deviceName: String? = nil,
        productName: String? = nil,
        productType: String? = nil,
        lastBackupDate: Date? = nil,
        encryptionState: DeviceBackupEncryptionState = .unknown
    ) {
        self.state = state
        self.displayName = displayName
        self.deviceName = deviceName
        self.productName = productName
        self.productType = productType
        self.lastBackupDate = lastBackupDate
        self.encryptionState = encryptionState
    }
}

private struct DeviceBackupMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

private func firstString(in dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
    }
    return nil
}

private func firstDate(in dict: [String: Any], keys: [String]) -> Date? {
    for key in keys {
        if let value = dict[key] as? Date {
            return value
        }
        if let value = dict[key] as? String {
            if let parsed = ISO8601DateFormatter().date(from: value) {
                return parsed
            }
        }
    }
    return nil
}

private func encryptionState(in dict: [String: Any]) -> DeviceBackupEncryptionState {
    for key in ["Is Encrypted", "IsEncrypted", "Encrypted"] {
        if let value = dict[key] as? Bool {
            return value ? .encrypted : .notEncrypted
        }
        if let value = dict[key] as? String {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "1"].contains(normalized) {
                return .encrypted
            }
            if ["false", "no", "0"].contains(normalized) {
                return .notEncrypted
            }
        }
    }
    return .unknown
}

private let deviceBackupResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]
