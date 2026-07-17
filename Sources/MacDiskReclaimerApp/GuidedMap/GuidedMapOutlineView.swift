import SwiftUI
import ReclaimerCore

struct GuidedMapOutlineView: View {
    let snapshot: GuidedMapSnapshot
    @Binding var rootID: String
    @Binding var selectedID: String?
    var visibleNodeIDs: Set<String>? = nil

    private var nodesByID: [String: GuidedMapNode] {
        Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
    }

    private var visibleNodes: [GuidedMapNode] {
        guard let root = nodesByID[rootID] else { return [] }
        return root.childIDs.compactMap { nodesByID[$0] }.filter {
            visibleNodeIDs?.contains($0.id) ?? true
        }.sorted {
            if $0.allocatedBytes == $1.allocatedBytes { return $0.displayName < $1.displayName }
            return $0.allocatedBytes > $1.allocatedBytes
        }
    }

    var body: some View {
        List(visibleNodes, selection: $selectedID) { node in
            HStack {
                Button {
                    selectedID = node.id
                    if !node.childIDs.isEmpty { rootID = node.id }
                } label: {
                    Label(node.displayName, systemImage: node.childIDs.isEmpty ? "doc" : "folder")
                }
                .buttonStyle(.plain)
                Spacer()
                Text(ByteFormat.string(node.allocatedBytes))
                    .foregroundStyle(.secondary)
            }
            .tag(node.id)
            .accessibilityLabel("\(node.displayName), \(ByteFormat.string(node.allocatedBytes)), \(node.measurementState.rawValue)")
        }
        .accessibilityIdentifier("guided-map.outline")
    }
}
