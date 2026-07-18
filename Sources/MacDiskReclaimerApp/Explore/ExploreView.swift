import SwiftUI
import ReclaimerCore

private enum ExploreMode: String, CaseIterable, Identifiable {
    case map
    case outline
    case tools

    var id: String { rawValue }

    var label: String {
        switch self {
        case .map: "Map"
        case .outline: "Outline"
        case .tools: "Tools"
        }
    }
}

struct ExploreView: View {
    @Bindable var model: DashboardModel
    @State private var rootID = ""
    @State private var selectedID: String?
    @State private var mode: ExploreMode = .map
    @State private var filter = ExploreFilter()
    @State private var reviewDestination: StorageReviewDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch mode {
            case .map, .outline:
                mapWorkspace
            case .tools:
                ExploreToolsView { reviewDestination = $0 }
            }
        }
        .padding(22)
        .navigationTitle("Explore")
        .sheet(item: $reviewDestination) { destination in
            StorageReviewSheet(model: model, destination: destination)
        }
        .onAppear { rootID = model.latestGuidedMap?.rootID ?? "" }
        .onChange(of: model.latestGuidedMap?.scanID) { _, _ in
            rootID = model.latestGuidedMap?.rootID ?? ""
            selectedID = nil
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                headerText
                Spacer()
                modePicker
            }
            VStack(alignment: .leading, spacing: 12) {
                headerText
                modePicker
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Explore storage")
                .font(.largeTitle.bold())
            Text(mode == .tools
                 ? "Open a focused, review-first workspace. Nothing is selected or cleaned automatically."
                 : "Map area represents allocated bytes. Map selection never selects cleanup.")
                .foregroundStyle(.secondary)
        }
    }

    private var modePicker: some View {
        Picker("Explore view", selection: $mode) {
            ForEach(ExploreMode.allCases) { item in
                Text(item.label)
                    .tag(item)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 270)
        .accessibilityIdentifier("explore.mode")
    }

    @ViewBuilder
    private var mapWorkspace: some View {
        if let map = model.latestGuidedMap {
            filters
            if mode == .outline {
                GuidedMapOutlineView(
                    snapshot: map,
                    rootID: $rootID,
                    selectedID: $selectedID,
                    visibleNodeIDs: filter.matchingIDs(in: map)
                )
            } else {
                GuidedTreemapView(
                    snapshot: map,
                    rootID: $rootID,
                    selectedID: $selectedID,
                    visibleNodeIDs: filter.matchingIDs(in: map)
                )
                .frame(maxHeight: .infinity)
            }
            GuidedMapInspectorView(
                node: map.nodes.first { $0.id == selectedID },
                onRequestReview: { reviewDestination = $0 }
            )
        } else {
            ContentUnavailableView(
                "Scan before exploring the map",
                systemImage: "square.grid.3x3",
                description: Text("Ryddi does not start a scan automatically. Storage tools remain available in the Tools view.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                filterControls
            }
            VStack(alignment: .leading) {
                filterControls
            }
        }
    }

    @ViewBuilder
    private var filterControls: some View {
        TextField("Search names or paths", text: $filter.searchText)
            .textFieldStyle(.roundedBorder)
        Picker("Category", selection: $filter.category) {
            Text("All categories").tag(GuidedMapCategory?.none)
            ForEach(GuidedMapCategory.allCases, id: \.self) { category in
                Text(category.rawValue).tag(Optional(category))
            }
        }
        Picker("Minimum size", selection: $filter.minimumSize) {
            ForEach(ExploreMinimumSize.allCases) { size in
                Text(size.label).tag(size)
            }
        }
    }
}

private struct ExploreToolsView: View {
    let open: (StorageReviewDestination) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                toolGroup(
                    "Everyday storage",
                    destinations: [.applications, .cloudFootprint, .downloads, .browserCaches, .deviceBackups]
                )
                toolGroup(
                    "Developer storage",
                    destinations: [.containers, .agentStorage]
                )
                Label(
                    "Each workspace starts with review. Destructive actions still require their own safety checks and confirmation.",
                    systemImage: "checkmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("explore.tools")
    }

    private func toolGroup(_ title: String, destinations: [StorageReviewDestination]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(destinations) { destination in
                    Button { open(destination) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: destination.systemImage)
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(destination.title)
                                    .font(.headline)
                                Text(destination.summary)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ExploreToolButtonStyle())
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator.opacity(0.45), lineWidth: 1)
                    }
                    .accessibilityIdentifier("explore.tool.\(destination.rawValue)")
                    .accessibilityHint("Opens a review workspace. Nothing is selected automatically.")
                }
            }
        }
    }
}

private struct ExploreToolButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}

struct StorageReviewSheet: View {
    let model: DashboardModel
    let destination: StorageReviewDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .applications:
                    AppReviewView(model: model)
                case .cloudFootprint:
                    CloudStorageWorkspaceView(model: model)
                case .containers:
                    ContainerInventoryView(model: model)
                case .downloads:
                    DownloadsReviewView(model: model)
                case .browserCaches:
                    BrowserCacheReviewView(model: model)
                case .deviceBackups:
                    DeviceBackupReviewView(model: model)
                case .agentStorage:
                    AgentStorageReviewView(model: model)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("storage-review.done")
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 980, minHeight: 600, idealHeight: 760)
        .task {
            switch destination {
            case .applications where model.appReview == nil:
                await model.reviewApps()
            case .containers where model.containerInventory == nil:
                await model.inspectContainers()
            case .downloads where model.downloadsReview == nil:
                await model.reviewDownloads()
            case .browserCaches where model.browserCacheReview == nil:
                await model.reviewBrowserCaches()
            case .deviceBackups where model.deviceBackupReview == nil:
                await model.reviewDeviceBackups()
            case .agentStorage where model.agentStorageReview == nil:
                await model.reviewAgentStorage()
            case .cloudFootprint, .applications, .containers, .downloads,
                 .browserCaches, .deviceBackups, .agentStorage:
                break
            }
        }
    }
}
