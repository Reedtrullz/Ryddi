import SwiftUI
import ReclaimerCore

enum StorageReviewDestination: String, CaseIterable, Identifiable, Hashable {
    case applications
    case cloudFootprint
    case containers
    case downloads
    case browserCaches
    case deviceBackups
    case agentStorage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: "Apps & Leftovers"
        case .cloudFootprint: "Cloud Footprint"
        case .containers: "Containers"
        case .downloads: "Downloads"
        case .browserCaches: "Browser Caches"
        case .deviceBackups: "Device Backups"
        case .agentStorage: "AI Agent Storage"
        }
    }

    var buttonLabel: String {
        switch self {
        case .applications: "Review app storage"
        case .cloudFootprint: "Review cloud footprint"
        case .containers: "Inspect reclaim options"
        case .downloads: "Review downloads"
        case .browserCaches: "Review browser caches"
        case .deviceBackups: "Review device backups"
        case .agentStorage: "Review agent storage"
        }
    }

    var systemImage: String {
        switch self {
        case .applications: "app.dashed"
        case .cloudFootprint: "externaldrive.connected.to.line.below"
        case .containers: "shippingbox"
        case .downloads: "arrow.down.circle"
        case .browserCaches: "globe"
        case .deviceBackups: "iphone"
        case .agentStorage: "brain.head.profile"
        }
    }

    var summary: String {
        switch self {
        case .applications: "Group installed apps and related files by owner before deciding anything."
        case .cloudFootprint: "Review what Dropbox, Google Drive, and MEGA currently allocate on this Mac."
        case .containers: "Separate unused Docker build cache from protected Colima and container state."
        case .downloads: "Find large and old downloads for an item-by-item Finder review."
        case .browserCaches: "Inspect browser-owned caches without touching profiles, logins, or bookmarks."
        case .deviceBackups: "Understand local iPhone and iPad backups as valuable restore points."
        case .agentStorage: "Separate rebuildable agent cache from valuable sessions and protected state."
        }
    }
}

extension GuidedMapNode {
    var storageReviewDestination: StorageReviewDestination? {
        let searchableText = [displayName, path ?? ""]
            .joined(separator: " ")
            .lowercased()
        if searchableText.contains("colima") || searchableText.contains("docker") {
            return .containers
        }
        if searchableText.contains("dropbox")
            || searchableText.contains("google drive")
            || displayName.caseInsensitiveCompare("MEGA") == .orderedSame
            || searchableText.contains("/mega/")
            || searchableText.hasSuffix("/mega") {
            return .cloudFootprint
        }
        if category == .applications {
            return .applications
        }
        return nil
    }
}

struct GuidedMapInspectorView: View {
    let node: GuidedMapNode?
    var onRequestReview: ((StorageReviewDestination) -> Void)?

    init(
        node: GuidedMapNode?,
        onRequestReview: ((StorageReviewDestination) -> Void)? = nil
    ) {
        self.node = node
        self.onRequestReview = onRequestReview
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
                    if let destination = node.storageReviewDestination,
                       let onRequestReview {
                        Button {
                            onRequestReview(destination)
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
