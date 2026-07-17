import SwiftUI
import ReclaimerCore

struct GuidedTreemapView: View {
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
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            breadcrumb
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
                                    rootID = node.id
                                    selectedID = nil
                                }
                            })
                            .accessibilityIdentifier("guided-map.node.\(node.id)")
                            .accessibilityLabel(accessibilityLabel(for: node))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            ForEach(ancestorIDs, id: \.self) { id in
                if let node = nodesByID[id] {
                    Button(node.displayName) {
                        rootID = id
                        selectedID = nil
                    }
                    .buttonStyle(.plain)
                    if id != ancestorIDs.last {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.caption)
        .accessibilityIdentifier("guided-map.breadcrumb")
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
}
