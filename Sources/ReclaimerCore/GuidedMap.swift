import Foundation

public enum GuidedMapCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case applications
    case personalFiles
    case developerFiles
    case media
    case caches
    case system
    case otherMeasured
    case limitedVisibility
}

public enum GuidedMapMeasurementState: String, Codable, Hashable, Sendable {
    case complete
    case bounded
    case limited
}

public enum GuidedMapNodeKind: String, Codable, Hashable, Sendable {
    case item
    case aggregate
    case parentRemainder
    case limitedVisibility
}

public struct GuidedMapNode: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let parentID: String?
    public let path: String?
    public let displayName: String
    public let allocatedBytes: Int64
    public let category: GuidedMapCategory
    public let measurementState: GuidedMapMeasurementState
    public let kind: GuidedMapNodeKind
    public let childIDs: [String]

    public init(
        id: String,
        parentID: String?,
        path: String?,
        displayName: String,
        allocatedBytes: Int64,
        category: GuidedMapCategory,
        measurementState: GuidedMapMeasurementState,
        kind: GuidedMapNodeKind,
        childIDs: [String]
    ) {
        self.id = id
        self.parentID = parentID
        self.path = path
        self.displayName = displayName
        self.allocatedBytes = max(0, allocatedBytes)
        self.category = category
        self.measurementState = measurementState
        self.kind = kind
        self.childIDs = childIDs
    }
}

public struct GuidedMapSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let scanID: String
    public let capturedAt: Date
    public let scopeDescription: String
    public let volumeCapacityBytes: Int64
    public let volumeAvailableBytes: Int64
    public let measuredAllocatedBytes: Int64
    public let evidenceState: GuidedMapMeasurementState
    public let rootID: String
    public let nodes: [GuidedMapNode]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        scanID: String,
        capturedAt: Date,
        scopeDescription: String,
        volumeCapacityBytes: Int64,
        volumeAvailableBytes: Int64,
        measuredAllocatedBytes: Int64,
        evidenceState: GuidedMapMeasurementState,
        rootID: String,
        nodes: [GuidedMapNode]
    ) {
        self.schemaVersion = schemaVersion
        self.scanID = scanID
        self.capturedAt = capturedAt
        self.scopeDescription = scopeDescription
        self.volumeCapacityBytes = max(0, volumeCapacityBytes)
        self.volumeAvailableBytes = max(0, volumeAvailableBytes)
        self.measuredAllocatedBytes = max(0, measuredAllocatedBytes)
        self.evidenceState = evidenceState
        self.rootID = rootID
        self.nodes = nodes
    }
}

public struct GuidedMapInput: Sendable {
    public let scanID: String
    public let capturedAt: Date
    public let scopeDescription: String
    public let coverage: ScanCoverage
    public let diskStatus: DiskStatusSnapshot
    public let drillDown: DiskDrillDownReport

    public init(
        scanID: String,
        capturedAt: Date,
        scopeDescription: String,
        coverage: ScanCoverage,
        diskStatus: DiskStatusSnapshot,
        drillDown: DiskDrillDownReport
    ) {
        self.scanID = scanID
        self.capturedAt = capturedAt
        self.scopeDescription = scopeDescription
        self.coverage = coverage
        self.diskStatus = diskStatus
        self.drillDown = drillDown
    }
}

public enum GuidedMapBuilder {
    public static func build(input: GuidedMapInput) -> GuidedMapSnapshot {
        let state = measurementState(for: input.coverage.state)
        let rootID = "guided-map-root:\(input.scanID)"
        let measured = max(0, input.drillDown.totalAllocatedSize)
        let capacity = max(0, input.diskStatus.totalBytes ?? 0)
        let available = max(0, input.diskStatus.displayFreeBytes ?? 0)
        let used = capacity > 0 ? max(0, capacity - available) : measured
        let limitedBytes = input.coverage.state == .degraded ? max(0, used - measured) : 0

        var nodes: [GuidedMapNode] = []
        var rootChildIDs: [String] = []
        for root in input.drillDown.rootNodes {
            let nodeID = itemID(path: root.path)
            rootChildIDs.append(nodeID)
            materialize(root, parentID: rootID, state: state, allocatedOverride: nil, into: &nodes)
        }
        if limitedBytes > 0 {
            let id = "\(rootID):limited"
            rootChildIDs.append(id)
            nodes.append(GuidedMapNode(
                id: id,
                parentID: rootID,
                path: nil,
                displayName: "Limited visibility",
                allocatedBytes: limitedBytes,
                category: .limitedVisibility,
                measurementState: .limited,
                kind: .limitedVisibility,
                childIDs: []
            ))
        }

        let rootAllocated = measured + limitedBytes
        nodes.insert(GuidedMapNode(
            id: rootID,
            parentID: nil,
            path: nil,
            displayName: input.diskStatus.volumeName ?? "Mac storage",
            allocatedBytes: rootAllocated,
            category: .otherMeasured,
            measurementState: state,
            kind: .aggregate,
            childIDs: rootChildIDs
        ), at: 0)

        return GuidedMapSnapshot(
            scanID: input.scanID,
            capturedAt: input.capturedAt,
            scopeDescription: input.scopeDescription,
            volumeCapacityBytes: capacity,
            volumeAvailableBytes: available,
            measuredAllocatedBytes: measured,
            evidenceState: state,
            rootID: rootID,
            nodes: nodes
        )
    }

    private static func materialize(
        _ source: DiskDrillDownNode,
        parentID: String,
        state: GuidedMapMeasurementState,
        allocatedOverride: Int64?,
        into nodes: inout [GuidedMapNode]
    ) {
        let id = itemID(path: source.path)
        let allocated = max(0, allocatedOverride ?? source.allocatedSize)
        var remaining = allocated
        var childIDs: [String] = []
        var childSources: [(DiskDrillDownNode, Int64)] = []

        for child in source.children where remaining > 0 {
            let childBytes = min(max(0, child.allocatedSize), remaining)
            guard childBytes > 0 else { continue }
            remaining -= childBytes
            childIDs.append(itemID(path: child.path))
            childSources.append((child, childBytes))
        }

        if remaining > 0, !source.children.isEmpty || source.omittedAllocatedSize > 0 {
            childIDs.append("\(id):remainder")
        }

        nodes.append(GuidedMapNode(
            id: id,
            parentID: parentID,
            path: source.path,
            displayName: source.displayName,
            allocatedBytes: allocated,
            category: category(for: source),
            measurementState: state,
            kind: .item,
            childIDs: childIDs
        ))

        for (child, childBytes) in childSources {
            materialize(child, parentID: id, state: state, allocatedOverride: childBytes, into: &nodes)
        }
        if remaining > 0, childIDs.last == "\(id):remainder" {
            nodes.append(GuidedMapNode(
                id: "\(id):remainder",
                parentID: id,
                path: nil,
                displayName: "Other measured items",
                allocatedBytes: remaining,
                category: .otherMeasured,
                measurementState: state,
                kind: .parentRemainder,
                childIDs: []
            ))
        }
    }

    private static func measurementState(for state: ScanCoverageState) -> GuidedMapMeasurementState {
        switch state {
        case .complete: .complete
        case .bounded: .bounded
        case .degraded: .limited
        }
    }

    private static func itemID(path: String) -> String {
        "guided-map-item:\(URL(fileURLWithPath: path).standardizedFileURL.path)"
    }

    private static func category(for node: DiskDrillDownNode) -> GuidedMapCategory {
        category(category: node.category, path: node.path)
    }

    static func category(category: String, path: String) -> GuidedMapCategory {
        let typedCategory = category.lowercased()
        if typedCategory.contains("application") { return .applications }
        if typedCategory.contains("developer")
            || typedCategory.contains("xcode")
            || typedCategory.contains("package")
            || typedCategory.contains("container")
            || typedCategory.contains("codex") {
            return .developerFiles
        }
        if typedCategory.contains("cache") || typedCategory.contains("temporary") || typedCategory.contains("log") {
            return .caches
        }
        if typedCategory.contains("photo")
            || typedCategory.contains("video")
            || typedCategory.contains("music")
            || typedCategory.contains("media")
            || typedCategory.contains("creative") {
            return .media
        }
        if typedCategory.contains("system") { return .system }
        if typedCategory.contains("personal")
            || typedCategory.contains("document")
            || typedCategory.contains("download")
            || typedCategory.contains("desktop") {
            return .personalFiles
        }

        let components = Set(
            URL(fileURLWithPath: path).standardizedFileURL.pathComponents.map {
                $0.lowercased()
            }
        )
        if !components.isDisjoint(with: ["applications"]) { return .applications }
        if !components.isDisjoint(with: ["developer", "developers", "xcode", "deriveddata", "node_modules", ".build", ".swiftpm"]) {
            return .developerFiles
        }
        if !components.isDisjoint(with: ["caches", ".cache", "tmp", "temporaryitems", "logs"]) { return .caches }
        if !components.isDisjoint(with: ["pictures", "photos", "movies", "music"]) { return .media }
        if components.contains("system") { return .system }
        if !components.isDisjoint(with: ["documents", "downloads", "desktop"]) { return .personalFiles }
        return .otherMeasured
    }
}
