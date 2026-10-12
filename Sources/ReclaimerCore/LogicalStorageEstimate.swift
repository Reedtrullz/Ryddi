import Foundation

/// A union of logical path estimates, not a measurement of allocated or freed disk space.
public struct LogicalStorageEstimate: Encodable, Sendable, Equatable {
    public let logicalBytes: Int64
    public let saturated: Bool
    public static let uncertainty = "Logical estimates only. Allocated and physically reclaimed bytes are unknown: hardlinks, clones, sparse files and cloud placeholders may share or omit allocation. Moving to Trash retains data and does not prove freed space."

    private struct Node {
        var bytes: Int64 = 0
        var children: [String: Int] = [:]
    }

    public init(recommendations: [ReclaimRecommendation]) {
        var nodes = [Node()]
        for recommendation in recommendations {
            let components = URL(fileURLWithPath: recommendation.path).standardizedFileURL.pathComponents
            var index = 0
            for component in components {
                if let child = nodes[index].children[component] {
                    index = child
                } else {
                    let child = nodes.count
                    nodes[index].children[component] = child
                    nodes.append(Node())
                    index = child
                }
            }
            nodes[index].bytes = max(nodes[index].bytes, recommendation.reclaimableBytes)
        }
        var saturated = false
        // Children are always created after parents. A parent estimate covers descendants;
        // inconsistent smaller parent estimates must not hide known descendant bytes.
        for index in nodes.indices.reversed() {
            var descendants: Int64 = 0
            for child in nodes[index].children.values {
                let (sum, overflow) = descendants.addingReportingOverflow(nodes[child].bytes)
                descendants = overflow ? Int64.max : sum
                saturated = saturated || overflow
            }
            nodes[index].bytes = max(nodes[index].bytes, descendants)
        }
        logicalBytes = nodes[0].bytes
        self.saturated = saturated
    }

    private enum CodingKeys: String, CodingKey {
        case basis, logicalBytes, allocatedBytes, physicalReclaimedBytes, saturated, uncertainty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("logical-path-union-estimate", forKey: .basis)
        try container.encode(logicalBytes, forKey: .logicalBytes)
        try container.encodeNil(forKey: .allocatedBytes)
        try container.encodeNil(forKey: .physicalReclaimedBytes)
        try container.encode(saturated, forKey: .saturated)
        try container.encode(Self.uncertainty, forKey: .uncertainty)
    }
}
