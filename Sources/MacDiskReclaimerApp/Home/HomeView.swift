import SwiftUI
import ReclaimerCore

struct HomeView: View {
    @Bindable var model: DashboardModel
    let navigate: (DashboardPrimaryDestination) -> Void
    @Environment(\.openSettings) private var openSettings
    @State private var showCleanupReview = false
    @State private var mapRootID = ""
    @State private var selectedMapNodeID: String?
    @State private var reclaimDestination: GuidedReclaimDestination?

    private var home: HomeSnapshot { model.homeSnapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                mapContent
                suggestions
            }
            .padding(22)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Home")
        .sheet(isPresented: $showCleanupReview) {
            CleanupReviewView(model: model)
        }
        .sheet(item: $reclaimDestination) { destination in
            GuidedReclaimReviewView(model: model, destination: destination)
        }
        .onAppear { synchronizeMapRoot() }
        .onChange(of: model.latestGuidedMap?.scanID) { _, _ in synchronizeMapRoot() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.largeTitle.bold())
                Text(evidenceLine)
                    .foregroundStyle(.secondary)
                if let map = home.map {
                    Text("Measured \(ByteFormat.string(map.measuredAllocatedBytes)) allocated. This is not a promise of reclaim.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            primaryActionButton
        }
    }

    @ViewBuilder
    private var mapContent: some View {
        if let map = home.map {
            GroupBox {
                GuidedTreemapView(
                    snapshot: map,
                    rootID: $mapRootID,
                    selectedID: $selectedMapNodeID
                )
                .frame(minHeight: 320, idealHeight: 410)
            } label: {
                HStack {
                    Label("Where your space went", systemImage: "square.grid.3x3")
                    Spacer()
                    Text(map.evidenceState.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
            }
            GuidedMapInspectorView(
                node: map.nodes.first { $0.id == selectedMapNodeID },
                onRequestReclaimHelp: { reclaimDestination = $0 }
            )
        } else {
            ContentUnavailableView {
                Label("See where your space went", systemImage: "internaldrive")
            } description: {
                Text("Ryddi waits for you to start. The scan measures your selected Mac folders and never cleans automatically.")
            }
            .frame(minHeight: 340)
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        if !home.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Worth your attention")
                        .font(.title2.bold())
                    Spacer()
                    if home.hiddenSuggestionCount > 0 {
                        Button("\(home.hiddenSuggestionCount) more") { navigate(.explore) }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(home.suggestions) { suggestion in
                        HomeSuggestionView(suggestion: suggestion)
                    }
                }
            }
        }
    }

    private var primaryActionButton: some View {
        Button(primaryActionLabel) { performPrimaryAction() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isWorking && home.primaryAction != .cancelScan)
            .accessibilityIdentifier("home.primary-action")
    }

    private var headline: String {
        if let map = home.map, map.volumeCapacityBytes > 0 {
            return "\(ByteFormat.string(map.volumeAvailableBytes)) available"
        }
        return model.diskStatus.statusLine
    }

    private var evidenceLine: String {
        guard let map = home.map else {
            return "Start a scan when you're ready. Nothing is cleaned or preselected."
        }
        return "\(map.scopeDescription) • \(map.evidenceState.rawValue.capitalized) visibility • \(map.capturedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var primaryActionLabel: String {
        switch home.primaryAction {
        case .scanMac: "Scan your Mac"
        case .cancelScan: "Cancel scan"
        case .reviewSuggestions: "Review suggestions"
        case .reviewAccess: "Review access"
        case .exploreLargestFiles: "Explore largest files"
        case .scanAgain: "Scan again"
        case .verifyCleanup: "Verify result"
        case .viewHistory: "View history"
        }
    }

    private func performPrimaryAction() {
        switch home.primaryAction {
        case .scanMac, .scanAgain, .verifyCleanup:
            model.startScan()
        case .cancelScan:
            model.cancelScan()
        case .reviewSuggestions:
            showCleanupReview = true
        case .reviewAccess:
            openSettings()
        case .exploreLargestFiles:
            navigate(.explore)
        case .viewHistory:
            navigate(.history)
        }
    }

    private func synchronizeMapRoot() {
        guard let map = home.map else {
            mapRootID = ""
            selectedMapNodeID = nil
            return
        }
        mapRootID = map.rootID
        selectedMapNodeID = nil
    }
}
