import SwiftUI
import ReclaimerCore

private enum CleanupReviewRoute: Identifiable {
    case all
    case suggestion(HomeSuggestion)

    var id: String {
        switch self {
        case .all: "all"
        case .suggestion(let suggestion): suggestion.id
        }
    }

    var suggestion: HomeSuggestion? {
        guard case .suggestion(let suggestion) = self else { return nil }
        return suggestion
    }
}

struct HomeView: View {
    @Bindable var model: DashboardModel
    let navigate: (DashboardPrimaryDestination) -> Void
    @Environment(\.openSettings) private var openSettings
    @State private var cleanupReviewRoute: CleanupReviewRoute?
    @State private var mapRootID = ""
    @State private var selectedMapNodeID: String?
    @State private var reviewDestination: StorageReviewDestination?

    private var home: HomeSnapshot { model.homeSnapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                scanFeedback
                reclaimCard
                limitedVisibilityGuidance
                suggestions
                mapContent
            }
            .padding(22)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Home")
        .sheet(item: $cleanupReviewRoute) { route in
            CleanupReviewView(model: model, suggestion: route.suggestion)
        }
        .sheet(item: $reviewDestination) { destination in
            StorageReviewSheet(model: model, destination: destination)
        }
        .onAppear { synchronizeMapRoot() }
        .onChange(of: model.latestGuidedMap?.scanID) { _, _ in synchronizeMapRoot() }
    }

    @ViewBuilder
    private var scanFeedback: some View {
        switch model.activity(for: .scan) {
        case .running(_, _, let progress, let message):
            HStack(alignment: .top, spacing: 12) {
                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 52)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.headline)
                    Text(scanProgressDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("home.scan-status")
        case .cancelling:
            HStack(alignment: .top, spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stopping scan…")
                        .font(.headline)
                    Text(scanCancellationDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("home.scan-status")
        case .idle, .failed:
            if let feedback = model.scanResultFeedback {
                scanResultPanel(feedback)
            } else if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("home.scan-result")
            }
        }
    }

    private var scanProgressDetail: String {
        if let map = home.map {
            return "The previous result from \(map.capturedAt.formatted(date: .abbreviated, time: .shortened)) stays visible until the new map and suggestions are ready."
        }
        return "Ryddi will show a storage map, coverage result, and clear next steps when this scan is ready."
    }

    private var scanCancellationDetail: String {
        if home.map != nil {
            return "Ryddi will keep the previous trustworthy result. Large filesystem operations can take a moment to reach a safe stopping point."
        }
        return "Ryddi is stopping at a safe point. Nothing will be saved or changed."
    }

    private func scanResultPanel(_ feedback: ScanResultFeedback) -> some View {
        let appearance = feedbackAppearance(feedback.style)
        return Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(feedback.title)
                    .font(.headline)
                Text(feedback.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: appearance.symbol)
                .foregroundStyle(appearance.color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("home.scan-result")
    }

    private func feedbackAppearance(_ style: ScanResultFeedbackStyle) -> (symbol: String, color: Color) {
        switch style {
        case .success: ("checkmark.circle.fill", .green)
        case .warning: ("exclamationmark.triangle.fill", .orange)
        case .stopped: ("stop.circle.fill", .secondary)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                headerCopy
                Spacer(minLength: 16)
                if home.reclaimSuggestion == nil {
                    primaryActionButton
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                headerCopy
                if home.reclaimSuggestion == nil {
                    primaryActionButton
                }
            }
        }
    }

    @ViewBuilder
    private var reclaimCard: some View {
        if let suggestion = home.reclaimSuggestion {
            HomeReclaimCard(
                suggestion: suggestion,
                isWorking: model.isWorking,
                visibilityIsLimited: home.map?.evidenceState == .limited
            ) {
                cleanupReviewRoute = .suggestion(suggestion)
            }
        }
    }

    private var headerCopy: some View {
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
    }

    private var recoveryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                reviewAccessButton
                setUpCloudReviewButton
            }
            VStack(alignment: .leading, spacing: 6) {
                reviewAccessButton
                setUpCloudReviewButton
            }
        }
    }

    private var reviewAccessButton: some View {
        Button {
            openSettings()
        } label: {
            Label("Review Access", systemImage: "lock.shield")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("home.review-access")
    }

    private var setUpCloudReviewButton: some View {
        Button {
            reviewDestination = .cloudFootprint
        } label: {
            Label("Set Up Cloud Review", systemImage: "externaldrive.connected.to.line.below")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("home.setup-cloud")
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
                onRequestReview: { reviewDestination = $0 }
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
        let secondarySuggestions = home.suggestions.filter { $0.kind != .safeMaintenance }
        if !secondarySuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(home.reclaimSuggestion == nil ? "Worth your attention" : "Other next steps")
                        .font(.title2.bold())
                    Spacer()
                    if home.hiddenSuggestionCount > 0 {
                        Button("\(home.hiddenSuggestionCount) more") { navigate(.explore) }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(secondarySuggestions) { suggestion in
                        HomeSuggestionView(
                            suggestion: suggestion,
                            isActionable: suggestion.kind.intent != .informational
                        ) {
                            performSuggestionAction(suggestion)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var limitedVisibilityGuidance: some View {
        if let map = home.map, map.evidenceState == .limited {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ryddi measured \(ByteFormat.string(map.measuredAllocatedBytes)), but macOS access limits hide \(ByteFormat.string(limitedVisibilityBytes(in: map))). Hidden storage is not reclaimable evidence.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    recoveryActions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Most storage is still hidden", systemImage: "eye.slash")
            }
            .accessibilityIdentifier("home.limited-visibility-guidance")
        }
    }

    private func limitedVisibilityBytes(in map: GuidedMapSnapshot) -> Int64 {
        map.nodes
            .filter { $0.category == .limitedVisibility }
            .reduce(0) { partial, node in
                let (sum, overflow) = partial.addingReportingOverflow(node.allocatedBytes)
                return overflow ? Int64.max : sum
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
        case .reviewReclaimableSpace: "Review safe maintenance"
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
        case .reviewReclaimableSpace:
            if let suggestion = home.reclaimSuggestion {
                cleanupReviewRoute = .suggestion(suggestion)
            }
        case .reviewSuggestions:
            cleanupReviewRoute = .all
        case .reviewAccess:
            openSettings()
        case .exploreLargestFiles:
            navigate(.explore)
        case .viewHistory:
            navigate(.history)
        }
    }

    private func performSuggestionAction(_ suggestion: HomeSuggestion) {
        switch HomeSuggestionRoute.resolve(suggestion: suggestion, findings: model.findings) {
        case .cleanup:
            cleanupReviewRoute = .suggestion(suggestion)
        case .storageReview(let destination):
            reviewDestination = destination
        case .explore:
            navigate(.explore)
        case .informational:
            break
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
