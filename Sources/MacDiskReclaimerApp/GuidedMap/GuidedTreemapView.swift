import SwiftUI
import ReclaimerCore

struct GuidedTreemapView: View {
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
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GuidedMapBreadcrumbView(snapshot: snapshot, rootID: rootID, onNavigate: navigate)
            GeometryReader { proxy in
                let frames = TreemapLayout().rectangles(
                    for: visibleNodes,
                    in: CGRect(origin: .zero, size: proxy.size)
                )
                ZStack(alignment: .topLeading) {
                    ForEach(visibleNodes) { node in
                        if let frame = frames[node.id], frame.width >= 1 {
                            Button {
                                selectedID = node.id
                            } label: {
                                tile(node, frame: frame)
                            }
                            .buttonStyle(.plain)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                if !node.childIDs.isEmpty {
                                    open(node)
                                }
                            })
                            .help(node.childIDs.isEmpty ? "Select \(node.displayName)" : "Select \(node.displayName); double-click to open")
                            .accessibilityIdentifier("guided-map.node.\(node.id)")
                            .accessibilityLabel(accessibilityLabel(for: node))
                            .accessibilityHint(node.childIDs.isEmpty
                                ? "Selects this item for inspection only."
                                : "Selects this item for inspection. Double-click or use the Open action to show its contents.")
                            .modifier(GuidedMapOpenActionModifier(node: node) {
                                open(node)
                            })
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func tile(_ node: GuidedMapNode, frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            categoryColor(node.category)
            Rectangle()
                .stroke(selectedID == node.id ? Color.accentColor : .white.opacity(0.35), lineWidth: selectedID == node.id ? 3 : 1)
            if frame.width > 80, frame.height > 42 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(ByteFormat.string(node.allocatedBytes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(7)
            }
            if !node.childIDs.isEmpty, frame.width > 54, frame.height > 34 {
                Image(systemName: "chevron.forward.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary.opacity(0.72))
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private func categoryColor(_ category: GuidedMapCategory) -> Color {
        switch category {
        case .applications: .blue.opacity(0.28)
        case .personalFiles: .cyan.opacity(0.30)
        case .developerFiles: .purple.opacity(0.28)
        case .media: .pink.opacity(0.28)
        case .caches: .orange.opacity(0.30)
        case .system: .gray.opacity(0.30)
        case .otherMeasured: .mint.opacity(0.24)
        case .limitedVisibility: .yellow.opacity(0.28)
        }
    }

    private func accessibilityLabel(for node: GuidedMapNode) -> String {
        "\(node.displayName), \(node.category.rawValue), \(ByteFormat.string(node.allocatedBytes)), \(node.measurementState.rawValue)"
    }

    private func open(_ node: GuidedMapNode) {
        navigate(node.id)
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

private struct GuidedMapOpenActionModifier: ViewModifier {
    let node: GuidedMapNode
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if node.childIDs.isEmpty {
            content
        } else {
            content.accessibilityAction(named: Text("Open \(node.displayName)"), action)
        }
    }
}
