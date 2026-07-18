import Foundation

public struct DiskDrillDownNode: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let displayName: String
    public let scopeName: String
    public let depth: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let isDirectory: Bool
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let category: String
    public let ownerHint: String?
    public let evidence: [String]
    public let childCount: Int
    public let omittedChildCount: Int
    public let omittedAllocatedSize: Int64
    public let children: [DiskDrillDownNode]

    public init(
        path: String,
        displayName: String,
        scopeName: String,
        depth: Int,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        isDirectory: Bool,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        category: String,
        ownerHint: String?,
        evidence: [String],
        childCount: Int,
        omittedChildCount: Int,
        omittedAllocatedSize: Int64,
        children: [DiskDrillDownNode]
    ) {
        self.path = path
        self.displayName = displayName
        self.scopeName = scopeName
        self.depth = depth
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.category = category
        self.ownerHint = ownerHint
        self.evidence = evidence
        self.childCount = childCount
        self.omittedChildCount = omittedChildCount
        self.omittedAllocatedSize = omittedAllocatedSize
        self.children = children
    }
}

public struct DiskDrillDownReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let generatedAt: Date
    public let scannedRoots: [ScanScope]
    public let nodeCount: Int
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let maxDepth: Int
    public let childLimit: Int
    public let rootNodes: [DiskDrillDownNode]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        generatedAt: Date,
        scannedRoots: [ScanScope],
        nodeCount: Int,
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        maxDepth: Int,
        childLimit: Int,
        rootNodes: [DiskDrillDownNode],
        nonClaims: [String]
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.scannedRoots = scannedRoots
        self.nodeCount = nodeCount
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.maxDepth = maxDepth
        self.childLimit = childLimit
        self.rootNodes = rootNodes
        self.nonClaims = nonClaims
    }
}

public enum DiskDrillDownBuilder {
    public static func build(
        findings: [Finding],
        scopes: [ScanScope],
        maxDepth: Int = 3,
        childLimit: Int = 8,
        generatedAt: Date = Date()
    ) -> DiskDrillDownReport {
        let uniqueFindings = uniqueByPath(findings)
        let mutableNodes = uniqueFindings.map { MutableDiskNode(finding: $0) }
        let nodesByPath = Dictionary(uniqueKeysWithValues: mutableNodes.map { (normalized($0.finding.path), $0) })
        var roots: [MutableDiskNode] = []

        for node in mutableNodes {
            let path = normalized(node.finding.path)
            if let parent = nearestParent(of: path, in: nodesByPath) {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
        }

        let orderedRoots = roots.sorted(by: sortMutableNodes)
        let reportRoots = orderedRoots.map {
            materialize($0, depth: 0, maxDepth: maxDepth, childLimit: childLimit)
        }
        let rootAccounting = orderedRoots

        return DiskDrillDownReport(
            generatedAt: generatedAt,
            scannedRoots: scopes,
            nodeCount: uniqueFindings.count,
            totalLogicalSize: rootAccounting.reduce(0) { $0 + $1.finding.logicalSize },
            totalAllocatedSize: rootAccounting.reduce(0) { $0 + $1.finding.allocatedSize },
            maxDepth: maxDepth,
            childLimit: childLimit,
            rootNodes: reportRoots,
            nonClaims: [
                "Disk drill-down is a bounded navigation view derived from scan findings; inaccessible, excluded, or deeper descendants may be absent.",
                "Parent rows include measured descendant bytes, so parent and child rows should not be added together as independent reclaim totals.",
                "Map nodes are informational only. Cleanup still requires item evidence, a dry-run plan, revalidation, and receipts.",
                "Allocated-size estimates can differ from immediate free-space gains because APFS clones, compression, snapshots, hard links, sparse files, and purgeable storage affect accounting."
            ]
        )
    }

    private static func materialize(
        _ node: MutableDiskNode,
        depth: Int,
        maxDepth: Int,
        childLimit: Int
    ) -> DiskDrillDownNode {
        let orderedChildren = node.children.sorted(by: sortMutableNodes)
        let visibleChildren = depth < maxDepth
            ? Array(orderedChildren.prefix(childLimit))
            : []
        let omittedChildren = max(0, orderedChildren.count - visibleChildren.count)
        let omittedBytes = orderedChildren.dropFirst(visibleChildren.count).reduce(0) { $0 + $1.finding.allocatedSize }
        let finding = node.finding

        return DiskDrillDownNode(
            path: finding.path,
            displayName: finding.displayName,
            scopeName: finding.scopeName,
            depth: depth,
            logicalSize: finding.logicalSize,
            allocatedSize: finding.allocatedSize,
            itemCount: measuredItemCount(from: finding),
            isDirectory: finding.isDirectory,
            safetyClass: finding.safetyClass,
            actionKind: finding.actionKind,
            category: finding.primaryCategory,
            ownerHint: finding.ownerHint,
            evidence: Array(finding.evidence.prefix(3).map(\.message)),
            childCount: orderedChildren.count,
            omittedChildCount: omittedChildren,
            omittedAllocatedSize: omittedBytes,
            children: visibleChildren.map {
                materialize($0, depth: depth + 1, maxDepth: maxDepth, childLimit: childLimit)
            }
        )
    }

    private static func uniqueByPath(_ findings: [Finding]) -> [Finding] {
        var seen: Set<String> = []
        return findings.filter { finding in
            seen.insert(normalized(finding.path)).inserted
        }
    }

    private static func nearestParent(
        of path: String,
        in nodesByPath: [String: MutableDiskNode]
    ) -> MutableDiskNode? {
        var candidate = normalized(
            URL(fileURLWithPath: path).deletingLastPathComponent().path
        )
        while candidate != path {
            if let parent = nodesByPath[candidate] {
                return parent
            }
            guard candidate != "/" else { return nil }
            let next = normalized(
                URL(fileURLWithPath: candidate).deletingLastPathComponent().path
            )
            guard next != candidate else { return nil }
            candidate = next
        }
        return nil
    }

    private static func normalized(_ path: String) -> String {
        var value = URL(fileURLWithPath: path).standardizedFileURL.path
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func sortMutableNodes(_ lhs: MutableDiskNode, _ rhs: MutableDiskNode) -> Bool {
        if lhs.finding.allocatedSize == rhs.finding.allocatedSize {
            return lhs.finding.path < rhs.finding.path
        }
        return lhs.finding.allocatedSize > rhs.finding.allocatedSize
    }

    private static func measuredItemCount(from finding: Finding) -> Int {
        for evidence in finding.evidence where evidence.kind == "items" {
            let fields = evidence.message.split { !$0.isNumber }
            if let first = fields.first, let count = Int(first) {
                return count
            }
        }
        return 0
    }
}

private final class MutableDiskNode {
    let finding: Finding
    var children: [MutableDiskNode] = []

    init(finding: Finding) {
        self.finding = finding
    }
}
