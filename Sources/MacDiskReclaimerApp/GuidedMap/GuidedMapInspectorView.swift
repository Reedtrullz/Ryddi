import SwiftUI
import ReclaimerCore

struct GuidedMapInspectorView: View {
    let node: GuidedMapNode?

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
