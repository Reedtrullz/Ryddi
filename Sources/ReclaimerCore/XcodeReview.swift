import Foundation

public enum XcodeArtifactKind: String, Codable, CaseIterable, Hashable, Sendable {
    case derivedData
    case moduleCache
    case documentationCache
    case products
    case archives
    case deviceSupport
    case simulatorDevices
    case simulatorRuntimes
    case simulatorLogs
    case previews
    case other

    public var label: String {
        switch self {
        case .derivedData: return "DerivedData"
        case .moduleCache: return "Module cache"
        case .documentationCache: return "Documentation cache"
        case .products: return "Products"
        case .archives: return "Archives"
        case .deviceSupport: return "Device support"
        case .simulatorDevices: return "Simulator devices"
        case .simulatorRuntimes: return "Simulator runtimes"
        case .simulatorLogs: return "Simulator logs"
        case .previews: return "SwiftUI previews"
        case .other: return "Other Xcode storage"
        }
    }

    public var isRebuildableCache: Bool {
        switch self {
        case .derivedData, .moduleCache, .documentationCache, .products:
            return true
        case .archives, .deviceSupport, .simulatorDevices, .simulatorRuntimes, .simulatorLogs, .previews, .other:
            return false
        }
    }

    public var isSimulatorState: Bool {
        switch self {
        case .simulatorDevices, .simulatorRuntimes, .simulatorLogs, .previews:
            return true
        case .derivedData, .moduleCache, .documentationCache, .products, .archives, .deviceSupport, .other:
            return false
        }
    }

    public var nativeCleanupHint: String {
        switch self {
        case .derivedData:
            return "Quit Xcode/build processes before removing DerivedData; Xcode will rebuild it."
        case .moduleCache, .documentationCache, .products:
            return "Quit Xcode first; these caches can be rebuilt but the next build or lookup may be slower."
        case .archives:
            return "Prefer Xcode Organizer for archive review; archives may be needed for distribution or symbolication."
        case .deviceSupport:
            return "Review OS versions before removal; device support can be needed for symbolication and device debugging."
        case .simulatorDevices:
            return "Prefer `xcrun simctl delete unavailable` or Simulator/Xcode UI after reviewing app data."
        case .simulatorRuntimes:
            return "Prefer Xcode Settings > Platforms for runtime removal; avoid raw deletion of active runtimes."
        case .simulatorLogs:
            return "Quit Xcode/Simulator and keep recent logs if actively debugging."
        case .previews:
            return "Quit Xcode before reviewing SwiftUI preview simulator data."
        case .other:
            return "Use Xcode or Finder review before removing unknown developer state."
        }
    }
}

public struct XcodeReviewItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let displayName: String
    public let kind: XcodeArtifactKind
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let modificationDate: Date?
    public let ageDays: Int?
    public let signals: [String]
    public let recommendation: String
    public let guidance: [String]

    public init(
        id: String = UUID().uuidString,
        path: String,
        displayName: String,
        kind: XcodeArtifactKind,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        modificationDate: Date? = nil,
        ageDays: Int? = nil,
        signals: [String],
        recommendation: String,
        guidance: [String]
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.kind = kind
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.modificationDate = modificationDate
        self.ageDays = ageDays
        self.signals = signals
        self.recommendation = recommendation
        self.guidance = guidance
    }
}

public struct XcodeReviewRootSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: XcodeArtifactKind
    public let rootPath: String
    public let permissionState: PermissionState
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let nativeCleanupHint: String
    public let note: String

    public init(
        id: String = UUID().uuidString,
        kind: XcodeArtifactKind,
        rootPath: String,
        permissionState: PermissionState,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        nativeCleanupHint: String,
        note: String
    ) {
        self.id = id
        self.kind = kind
        self.rootPath = rootPath
        self.permissionState = permissionState
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.nativeCleanupHint = nativeCleanupHint
        self.note = note
    }
}

public struct XcodeProtectedStateRoot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let permissionState: PermissionState
    public let note: String

    public init(
        id: String = UUID().uuidString,
        path: String,
        permissionState: PermissionState,
        note: String
    ) {
        self.id = id
        self.path = path
        self.permissionState = permissionState
        self.note = note
    }
}

public struct XcodeReviewSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let itemCount: Int
    public let allocatedSize: Int64

    public init(name: String, itemCount: Int, allocatedSize: Int64) {
        self.name = name
        self.itemCount = itemCount
        self.allocatedSize = allocatedSize
    }
}

public struct XcodeReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let itemCount: Int
    public let displayedItemCount: Int
    public let rebuildableCacheBytes: Int64
    public let reviewRequiredBytes: Int64
    public let simulatorStateBytes: Int64
    public let rootSummaries: [XcodeReviewRootSummary]
    public let kindSummaries: [XcodeReviewSummary]
    public let largestItems: [XcodeReviewItem]
    public let protectedStateRoots: [XcodeProtectedStateRoot]
    public let guidance: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        itemCount: Int,
        displayedItemCount: Int,
        rebuildableCacheBytes: Int64,
        reviewRequiredBytes: Int64,
        simulatorStateBytes: Int64,
        rootSummaries: [XcodeReviewRootSummary],
        kindSummaries: [XcodeReviewSummary],
        largestItems: [XcodeReviewItem],
        protectedStateRoots: [XcodeProtectedStateRoot],
        guidance: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.itemCount = itemCount
        self.displayedItemCount = displayedItemCount
        self.rebuildableCacheBytes = rebuildableCacheBytes
        self.reviewRequiredBytes = reviewRequiredBytes
        self.simulatorStateBytes = simulatorStateBytes
        self.rootSummaries = rootSummaries
        self.kindSummaries = kindSummaries
        self.largestItems = largestItems
        self.protectedStateRoots = protectedStateRoots
        self.guidance = guidance
        self.nonClaims = nonClaims
    }
}

public struct XcodeReviewOptions: Hashable, Sendable {
    public let roots: [URL]
    public let protectedStateRoots: [URL]
    public let limit: Int
    public let oldDays: Int
    public let measurementDepth: Int
    public let includeMissingRoots: Bool

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: [URL]? = nil,
        protectedStateRoots: [URL]? = nil,
        limit: Int = 50,
        oldDays: Int = 180,
        measurementDepth: Int = 10,
        includeMissingRoots: Bool = true
    ) {
        let standardizedHome = home.standardizedFileURL
        self.roots = (roots ?? Self.defaultRoots(home: standardizedHome)).map { $0.standardizedFileURL }
        self.protectedStateRoots = (protectedStateRoots ?? Self.defaultProtectedStateRoots(home: standardizedHome)).map { $0.standardizedFileURL }
        self.limit = max(1, min(limit, 500))
        self.oldDays = max(1, min(oldDays, 3650))
        self.measurementDepth = max(0, min(measurementDepth, 32))
        self.includeMissingRoots = includeMissingRoots
    }

    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            home.appendingPathComponent("Library/Developer/Xcode/ModuleCache.noindex"),
            home.appendingPathComponent("Library/Developer/Xcode/DocumentationCache"),
            home.appendingPathComponent("Library/Developer/Xcode/Products"),
            home.appendingPathComponent("Library/Developer/Xcode/Archives"),
            home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
            home.appendingPathComponent("Library/Developer/Xcode/watchOS DeviceSupport"),
            home.appendingPathComponent("Library/Developer/Xcode/tvOS DeviceSupport"),
            home.appendingPathComponent("Library/Developer/CoreSimulator/Devices"),
            home.appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes"),
            home.appendingPathComponent("Library/Logs/CoreSimulator"),
            home.appendingPathComponent("Library/Developer/CoreSimulator/Logs"),
            home.appendingPathComponent("Library/Developer/Xcode/UserData/Previews/Simulator Devices")
        ]
    }

    public static func defaultProtectedStateRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Developer/Xcode/UserData"),
            home.appendingPathComponent("Library/Developer/Xcode/Accounts"),
            home.appendingPathComponent("Library/Developer/Xcode/Templates"),
            home.appendingPathComponent("Library/Preferences/com.apple.dt.Xcode.plist"),
            home.appendingPathComponent("Library/MobileDevice/Provisioning Profiles")
        ]
    }
}

public final class XcodeReviewScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func review(
        options: XcodeReviewOptions = XcodeReviewOptions(),
        createdAt: Date = Date()
    ) -> XcodeReviewReport {
        var summaries: [XcodeReviewRootSummary] = []
        var items: [XcodeReviewItem] = []

        for root in options.roots {
            let result = inspect(
                root: root,
                oldDays: options.oldDays,
                measurementDepth: options.measurementDepth,
                referenceDate: createdAt
            )
            if result.summary.permissionState != .missing || options.includeMissingRoots {
                summaries.append(result.summary)
            }
            items.append(contentsOf: result.items)
        }

        let sortedItems = items.sorted { lhs, rhs in
            if lhs.allocatedSize == rhs.allocatedSize {
                return lhs.path < rhs.path
            }
            return lhs.allocatedSize > rhs.allocatedSize
        }
        let logical = sortedItems.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = sortedItems.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let measuredCount = sortedItems.reduce(0) { $0 + max(1, $1.itemCount) }
        let rebuildable = sortedItems
            .filter { $0.kind.isRebuildableCache }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let simulator = sortedItems
            .filter { $0.kind.isSimulatorState }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let reviewRequired = sortedItems
            .filter { !$0.kind.isRebuildableCache }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let protected = options.protectedStateRoots.map { protectedStateRoot(for: $0) }

        return XcodeReviewReport(
            createdAt: createdAt,
            totalLogicalSize: logical,
            totalAllocatedSize: allocated,
            itemCount: measuredCount,
            displayedItemCount: min(sortedItems.count, options.limit),
            rebuildableCacheBytes: rebuildable,
            reviewRequiredBytes: reviewRequired,
            simulatorStateBytes: simulator,
            rootSummaries: summaries,
            kindSummaries: Self.kindSummaries(for: sortedItems),
            largestItems: Array(sortedItems.prefix(options.limit)),
            protectedStateRoots: protected,
            guidance: Self.guidance,
            nonClaims: Self.nonClaims
        )
    }

    private func inspect(
        root: URL,
        oldDays: Int,
        measurementDepth: Int,
        referenceDate: Date
    ) -> (summary: XcodeReviewRootSummary, items: [XcodeReviewItem]) {
        let root = root.standardizedFileURL
        let kind = Self.kind(for: root)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return (
                XcodeReviewRootSummary(
                    kind: kind,
                    rootPath: root.path,
                    permissionState: .missing,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    nativeCleanupHint: kind.nativeCleanupHint,
                    note: "Xcode review root does not exist at \(root.path)."
                ),
                []
            )
        }
        guard isDirectory.boolValue else {
            return (
                XcodeReviewRootSummary(
                    kind: kind,
                    rootPath: root.path,
                    permissionState: .unknown,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    nativeCleanupHint: kind.nativeCleanupHint,
                    note: "Configured Xcode review root is not a directory: \(root.path)."
                ),
                []
            )
        }
        guard fileManager.isReadableFile(atPath: root.path) else {
            return (
                XcodeReviewRootSummary(
                    kind: kind,
                    rootPath: root.path,
                    permissionState: .denied,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    nativeCleanupHint: kind.nativeCleanupHint,
                    note: "Xcode review root is not readable with current permissions: \(root.path)."
                ),
                []
            )
        }

        guard let children = itemURLs(for: root, kind: kind, measurementDepth: measurementDepth) else {
            return (
                XcodeReviewRootSummary(
                    kind: kind,
                    rootPath: root.path,
                    permissionState: .denied,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    nativeCleanupHint: kind.nativeCleanupHint,
                    note: "Could not list Xcode review root at \(root.path)."
                ),
                []
            )
        }

        let rootItems = children.map {
            item(
                for: $0,
                kind: kind,
                oldDays: oldDays,
                measurementDepth: measurementDepth,
                referenceDate: referenceDate
            )
        }
        let logical = rootItems.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = rootItems.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let count = rootItems.reduce(0) { $0 + max(1, $1.itemCount) }
        return (
            XcodeReviewRootSummary(
                kind: kind,
                rootPath: root.path,
                permissionState: .readable,
                logicalSize: logical,
                allocatedSize: allocated,
                itemCount: count,
                nativeCleanupHint: kind.nativeCleanupHint,
                note: "Measured Xcode \(kind.label) entries under \(root.path)."
            ),
            rootItems
        )
    }

    private func itemURLs(for root: URL, kind: XcodeArtifactKind, measurementDepth: Int) -> [URL]? {
        if kind == .archives {
            var archives: [URL] = []
            if let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: xcodeReviewResourceKeys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) {
                for case let child as URL in enumerator {
                    let depth = max(0, child.pathComponents.count - root.pathComponents.count)
                    if depth > measurementDepth {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard let values = try? child.resourceValues(forKeys: Set(xcodeReviewResourceKeys)) else { continue }
                    if values.isSymbolicLink == true {
                        enumerator.skipDescendants()
                        continue
                    }
                    if values.isDirectory == true, child.pathExtension.lowercased() == "xcarchive" {
                        archives.append(child)
                        enumerator.skipDescendants()
                    }
                }
            }
            if !archives.isEmpty {
                return archives.sorted { $0.path < $1.path }
            }
        }

        return try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: xcodeReviewResourceKeys,
            options: [.skipsHiddenFiles]
        )
    }

    private func item(
        for url: URL,
        kind: XcodeArtifactKind,
        oldDays: Int,
        measurementDepth: Int,
        referenceDate: Date
    ) -> XcodeReviewItem {
        let values = try? url.resourceValues(forKeys: Set(xcodeReviewResourceKeys))
        let measurement = measure(url: url, maxDepth: measurementDepth)
        let modified = values?.contentModificationDate
        let ageDays = modified.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: referenceDate).day ?? 0) }
        let isOld = (ageDays ?? 0) >= oldDays
        let isSymbolicLink = values?.isSymbolicLink ?? false
        let displayName = archiveDisplayName(for: url) ?? simulatorDeviceName(for: url) ?? url.lastPathComponent
        return XcodeReviewItem(
            path: url.path,
            displayName: displayName,
            kind: kind,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            itemCount: measurement.itemCount,
            isDirectory: values?.isDirectory ?? false,
            isSymbolicLink: isSymbolicLink,
            modificationDate: modified,
            ageDays: ageDays,
            signals: Self.signals(kind: kind, isOld: isOld, isSymbolicLink: isSymbolicLink),
            recommendation: Self.recommendation(kind: kind, isOld: isOld, isSymbolicLink: isSymbolicLink),
            guidance: Self.itemGuidance(kind: kind, isOld: isOld, isSymbolicLink: isSymbolicLink)
        )
    }

    private func protectedStateRoot(for url: URL) -> XcodeProtectedStateRoot {
        let url = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        let state: PermissionState
        let note: String
        if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            state = .missing
            note = "Protected Xcode developer state path is not present."
        } else if !fileManager.isReadableFile(atPath: url.path) {
            state = .denied
            note = "Protected Xcode developer state exists but is not readable; it remains outside Xcode cleanup review."
        } else {
            state = .readable
            note = "Protected Xcode developer state may contain snippets, templates, signing profiles, accounts, preferences, or user workflow state; it is intentionally not measured as cache."
        }
        return XcodeProtectedStateRoot(path: url.path, permissionState: state, note: note)
    }

    private func measure(url: URL, maxDepth: Int) -> XcodeReviewMeasurement {
        guard let values = try? url.resourceValues(forKeys: Set(xcodeReviewResourceKeys)) else {
            return XcodeReviewMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }
        if values.isSymbolicLink == true {
            return XcodeReviewMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return XcodeReviewMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1)
        }
        guard maxDepth > 0 else {
            return XcodeReviewMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: xcodeReviewResourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return XcodeReviewMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        for case let child as URL in enumerator {
            let depth = max(0, child.pathComponents.count - url.pathComponents.count)
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(xcodeReviewResourceKeys)) else { continue }
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
        return XcodeReviewMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: count)
    }

    private func archiveDisplayName(for url: URL) -> String? {
        guard url.pathExtension.lowercased() == "xcarchive" else { return nil }
        let infoURL = url.appendingPathComponent("Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dict = plist as? [String: Any]
        else {
            return nil
        }
        if let appProperties = dict["ApplicationProperties"] as? [String: Any] {
            if let name = xcodeFirstString(in: appProperties, keys: ["ApplicationName", "Name", "CFBundleDisplayName"]) {
                return "\(name).xcarchive"
            }
        }
        if let name = xcodeFirstString(in: dict, keys: ["Name", "ApplicationName", "CFBundleDisplayName"]) {
            return "\(name).xcarchive"
        }
        return nil
    }

    private func simulatorDeviceName(for url: URL) -> String? {
        let deviceURL = url.appendingPathComponent("device.plist")
        guard
            let data = try? Data(contentsOf: deviceURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dict = plist as? [String: Any],
            let name = xcodeFirstString(in: dict, keys: ["name", "Name", "deviceName"])
        else {
            return nil
        }
        return name
    }

    private static func kindSummaries(for items: [XcodeReviewItem]) -> [XcodeReviewSummary] {
        XcodeArtifactKind.allCases.compactMap { kind in
            let matches = items.filter { $0.kind == kind }
            guard !matches.isEmpty else { return nil }
            return XcodeReviewSummary(
                name: kind.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func kind(for url: URL) -> XcodeArtifactKind {
        let lower = url.path.lowercased()
        if lower.contains("/deriveddata") { return .derivedData }
        if lower.contains("/modulecache") { return .moduleCache }
        if lower.contains("/documentationcache") { return .documentationCache }
        if lower.contains("/products") { return .products }
        if lower.contains("/archives") { return .archives }
        if lower.contains("devicesupport") { return .deviceSupport }
        if lower.contains("/coresimulator/devices") { return .simulatorDevices }
        if lower.contains("/profiles/runtimes") { return .simulatorRuntimes }
        if lower.contains("/logs/coresimulator") || lower.contains("/coresimulator/logs") { return .simulatorLogs }
        if lower.contains("/previews/simulator devices") { return .previews }
        return .other
    }

    private static func signals(kind: XcodeArtifactKind, isOld: Bool, isSymbolicLink: Bool) -> [String] {
        var result = ["xcode", kind.rawValue]
        if kind.isRebuildableCache {
            result.append("rebuildable-cache")
        }
        if kind.isSimulatorState {
            result.append("simulator-state")
        }
        if isOld {
            result.append("old-xcode-item")
        }
        if isSymbolicLink {
            result.append("symlink-not-followed")
        }
        return result
    }

    private static func recommendation(kind: XcodeArtifactKind, isOld: Bool, isSymbolicLink: Bool) -> String {
        if isSymbolicLink {
            return "Manual review only; symbolic links are not followed or cleaned by Xcode Review."
        }
        switch kind {
        case .derivedData:
            return "Review for cleanup after quitting Xcode; this is rebuildable but the next build may be slower."
        case .moduleCache, .documentationCache, .products:
            return "Review after quitting Xcode; this cache is usually rebuildable but can slow the next build or lookup."
        case .archives:
            return "Review in Xcode Organizer before removal; archives may be needed for upload history, distribution, or symbolication."
        case .deviceSupport:
            return "Review OS versions before removal; device support can be needed for symbolication and physical device debugging."
        case .simulatorDevices:
            return isOld
                ? "Review simulator data before removal; prefer simctl or Xcode UI after confirming app data is disposable."
                : "Preserve by default; simulator devices can contain useful local app state."
        case .simulatorRuntimes:
            return "Review through Xcode Settings > Platforms; runtimes are large and should not be raw-deleted while active."
        case .simulatorLogs:
            return "Review diagnostic value first; keep recent logs if actively debugging."
        case .previews:
            return "Review after quitting Xcode; SwiftUI preview simulator data can usually be rebuilt."
        case .other:
            return "Manual Xcode storage review; Ryddi does not know enough to recommend cleanup."
        }
    }

    private static func itemGuidance(kind: XcodeArtifactKind, isOld: Bool, isSymbolicLink: Bool) -> [String] {
        var guidance = [kind.nativeCleanupHint]
        if isOld {
            guidance.append("Age is a review signal only; old Xcode data can still be useful for symbolication or debugging.")
        }
        if isSymbolicLink {
            guidance.append("Symbolic link was not followed while measuring.")
        }
        return guidance
    }

    public static let guidance = [
        "Quit Xcode, Simulator, and active build processes before cleanup decisions.",
        "Treat DerivedData and module/documentation/product caches differently from archives, device support, simulator devices, and runtimes.",
        "Prefer Xcode Organizer, Xcode Settings > Platforms, and `xcrun simctl` guidance over raw deletion for archives, runtimes, and simulator state.",
        "Keep Xcode UserData, snippets, signing profiles, accounts, templates, and preferences protected unless the user deliberately reviews them outside Ryddi."
    ]

    public static let nonClaims = [
        "Xcode Review is report-only; it does not delete, move, Trash, prune, purge, reset simulators, or modify Xcode files.",
        "Ryddi does not prove Xcode, Simulator, xcodebuild, or developer tools are idle; use active-handle checks and quit tools before cleanup.",
        "Xcode archive, device-support, simulator, and runtime classification is path-based and cannot prove the data is no longer needed.",
        "Xcode storage size is not promised immediate free-space recovery because APFS snapshots, hard links, clones, and purgeable storage can affect accounting."
    ]
}

private struct XcodeReviewMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

private func xcodeFirstString(in dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
    }
    return nil
}

private let xcodeReviewResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]
