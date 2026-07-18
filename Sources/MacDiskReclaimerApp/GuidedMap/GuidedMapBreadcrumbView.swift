import SwiftUI
import ReclaimerCore

struct GuidedMapBreadcrumbView: View {
    let snapshot: GuidedMapSnapshot
    let rootID: String
    let onNavigate: (String) -> Void

    private var nodesByID: [String: GuidedMapNode] {
        Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
    }

    private var ancestorIDs: [String] {
        var values: [String] = []
        var current: String? = rootID
        var visited: Set<String> = []
        while let id = current, visited.insert(id).inserted, let node = nodesByID[id] {
            values.append(id)
            current = node.parentID
        }
        return values.reversed()
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(ancestorIDs, id: \.self) { id in
                    if let node = nodesByID[id] {
                        Button(node.displayName) {
                            onNavigate(id)
                        }
                        .buttonStyle(.plain)
                        .disabled(id == rootID)
                        if id != ancestorIDs.last {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .font(.caption)
        .accessibilityIdentifier("guided-map.breadcrumb")
    }
}
