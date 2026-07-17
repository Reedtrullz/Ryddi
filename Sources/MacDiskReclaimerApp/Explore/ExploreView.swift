import SwiftUI
import ReclaimerCore

struct ExploreView: View {
    @Bindable var model: DashboardModel
    @State private var rootID = ""
    @State private var selectedID: String?
    @State private var showOutline = false
    @State private var filter = ExploreFilter()

    var body: some View {
        VStack(spacing: 12) {
            if let map = model.latestGuidedMap {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Explore storage").font(.largeTitle.bold())
                        Text("Map area represents allocated bytes. Map selection never selects cleanup.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("View", selection: $showOutline) {
                        Text("Treemap").tag(false)
                        Text("Outline").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                HStack {
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
                if showOutline {
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
                GuidedMapInspectorView(node: map.nodes.first { $0.id == selectedID })
            } else {
                ContentUnavailableView(
                    "Scan before exploring",
                    systemImage: "square.grid.3x3",
                    description: Text("Ryddi does not start a scan automatically.")
                )
            }
        }
        .padding(22)
        .navigationTitle("Explore")
        .onAppear { rootID = model.latestGuidedMap?.rootID ?? "" }
        .onChange(of: model.latestGuidedMap?.scanID) { _, _ in
            rootID = model.latestGuidedMap?.rootID ?? ""
            selectedID = nil
        }
    }
}
