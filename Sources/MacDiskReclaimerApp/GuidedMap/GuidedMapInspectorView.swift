import SwiftUI
import ReclaimerCore

enum GuidedReclaimDestination: String, Identifiable {
    case applications
    case containers

    var id: String { rawValue }

    var buttonLabel: String {
        switch self {
        case .applications: "Review app storage"
        case .containers: "Inspect reclaim options"
        }
    }
}

extension GuidedMapNode {
    var guidedReclaimDestination: GuidedReclaimDestination? {
        let searchableText = [displayName, path ?? ""]
            .joined(separator: " ")
            .lowercased()
        if searchableText.contains("colima") || searchableText.contains("docker") {
            return .containers
        }
        if category == .applications {
            return .applications
        }
        return nil
    }
}

struct GuidedMapInspectorView: View {
    let node: GuidedMapNode?
    var onRequestReclaimHelp: ((GuidedReclaimDestination) -> Void)?

    init(
        node: GuidedMapNode?,
        onRequestReclaimHelp: ((GuidedReclaimDestination) -> Void)? = nil
    ) {
        self.node = node
        self.onRequestReclaimHelp = onRequestReclaimHelp
    }

    var body: some View {
        GroupBox("Selected item") {
            if let node {
                VStack(alignment: .leading, spacing: 8) {
                    Text(node.displayName).font(.headline)
                    LabeledContent("Allocated", value: ByteFormat.string(node.allocatedBytes))
                    LabeledContent("Category", value: node.category.rawValue)
                    LabeledContent("Evidence", value: node.measurementState.rawValue)
                    Text("Map selection is for understanding only. Nothing is added to cleanup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let destination = node.guidedReclaimDestination,
                       let onRequestReclaimHelp {
                        Button {
                            onRequestReclaimHelp(destination)
                        } label: {
                            Label(destination.buttonLabel, systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Opens a review. Nothing is selected or removed automatically.")
                    }
                    if let path = node.path {
                        HStack {
                            Button("Quick Look") { PathActions.quickLook(path) }
                            Button("Reveal in Finder") { PathActions.revealInFinder(path) }
                            Menu("More") {
                                Button("Copy Path") { PathActions.copyPath(path) }
                                Button("Open in Terminal") {
                                    PathActions.openTerminal(at: path, isDirectory: !node.childIDs.isEmpty)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Select a rectangle or outline row to inspect it.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
