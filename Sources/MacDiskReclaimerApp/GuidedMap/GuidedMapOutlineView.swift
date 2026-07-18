import SwiftUI
import ReclaimerCore

struct GuidedMapOutlineView: View {
    let snapshot: GuidedMapSnapshot
    @Binding var rootID: String
    @Binding var selectedID: String?
    var visibleNodeIDs: Set<String>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        VStack(alignment: .leading, spacing: 8) {
            GuidedMapBreadcrumbView(snapshot: snapshot, rootID: rootID, onNavigate: navigate)
            List(visibleNodes, selection: $selectedID) { node in
                HStack(spacing: 10) {
                    Label(node.displayName, systemImage: node.childIDs.isEmpty ? "doc" : "folder")
                    Spacer()
                    Text(ByteFormat.string(node.allocatedBytes))
                        .foregroundStyle(.secondary)
                    if !node.childIDs.isEmpty {
                        Button {
                            navigate(node.id)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .help("Show contents of \(node.displayName)")
                        .accessibilityLabel("Show contents of \(node.displayName)")
                    }
                }
                .contentShape(Rectangle())
                .tag(node.id)
                .accessibilityLabel("\(node.displayName), \(ByteFormat.string(node.allocatedBytes)), \(node.measurementState.rawValue)")
                .modifier(GuidedOutlineOpenActionModifier(node: node) {
                    navigate(node.id)
                })
            }
            .accessibilityIdentifier("guided-map.outline")
        }
    }

    private func navigate(_ id: String) {
        let changes = {
            rootID = id
            selectedID = nil
        }
        if reduceMotion {
            changes()
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 1)) {
                changes()
            }
        }
    }
}

private struct GuidedOutlineOpenActionModifier: ViewModifier {
    let node: GuidedMapNode
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if node.childIDs.isEmpty {
            content
        } else {
            content.accessibilityAction(named: Text("Show contents of \(node.displayName)"), action)
        }
    }
}
