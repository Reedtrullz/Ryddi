import SwiftUI
import ReclaimerCore

struct AppReviewView: View {
    let model: DashboardModel
    @State private var includeSystemApps = false
    @State private var includeOrphans = true
    @State private var showSkipped = false
    @State private var selectedGroupID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                AppReviewOptionStrip(
                    includeSystemApps: $includeSystemApps,
                    includeOrphans: $includeOrphans,
                    isWorking: model.isWorking,
                    onReview: {
                        Task { await model.reviewApps(includeSystemApps: includeSystemApps, includeOrphans: includeOrphans) }
                    }
                )

                if let report = model.appReview {
                    AppReviewMetricStrip(report: report)

                    AppReviewWorkspace(
                        report: report,
                        selectedGroupID: $selectedGroupID,
                        isWorking: model.isWorking,
                        onPreviewUninstall: { group in
                            Task { await model.previewAppUninstall(group: group) }
                        }
                    )

                    AppReviewSafetyStrip(report: report)

                    if let preview = model.appUninstallPreview {
                        AppUninstallPreviewView(preview: preview, model: model)
                    }

                    AppReviewSkippedPathsView(report: report, showSkipped: $showSkipped)
                } else {
                    AppReviewEmptyState(
                        isWorking: model.isWorking,
                        onReview: {
                            Task { await model.reviewApps(includeSystemApps: includeSystemApps, includeOrphans: includeOrphans) }
                        }
                    )
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                headerText
                Spacer()
                headerBadge
            }

            VStack(alignment: .leading, spacing: 10) {
                headerText
                headerBadge
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apps & Leftovers")
                .font(.largeTitle.bold())
            Text("Review app-owned storage by owner before uninstalling apps or touching support files.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerBadge: some View {
        ReviewQueueStatusPill(text: "Review-only related files", color: .purple)
    }
}

struct AppReviewOptionStrip: View {
    @Binding var includeSystemApps: Bool
    @Binding var includeOrphans: Bool
    let isWorking: Bool
    let onReview: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                optionText
                Spacer()
                toggles
                reviewButton
            }

            VStack(alignment: .leading, spacing: 12) {
                optionText
                toggles
                reviewButton
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.45), lineWidth: 1)
                )
        }
    }

    private var optionText: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review scope")
                    .font(.headline)
                Text("Scan apps and app-owned support data. Ryddi reports related files; it does not remove them from this view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var toggles: some View {
        HStack(spacing: 14) {
            Toggle("System apps", isOn: $includeSystemApps)
                .toggleStyle(.switch)
                .controlSize(.small)
            Toggle("Orphan candidates", isOn: $includeOrphans)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var reviewButton: some View {
        Button(action: onReview) {
            Label(isWorking ? "Reviewing" : "Review Apps", systemImage: "app.dashed")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isWorking)
    }
}

struct AppReviewMetricStrip: View {
    let report: AppReviewReport

    var body: some View {
        LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, alignment: .leading, spacing: 12) {
            ReviewQueueMetricCard(systemImage: "app.dashed", title: "Installed", value: "\(report.installedApps.count)", detail: "apps found")
            ReviewQueueMetricCard(systemImage: "square.stack.3d.up", title: "Related Groups", value: "\(report.installedAppGroups.count)", detail: "installed owners", color: .blue)
            ReviewQueueMetricCard(systemImage: "questionmark.folder", title: "Orphans", value: "\(report.orphanGroups.count)", detail: "heuristic groups", color: .orange)
            ReviewQueueMetricCard(systemImage: "internaldrive", title: "Review Bytes", value: ByteFormat.string(report.reviewBytes), detail: "not auto-reclaim", color: .purple)
            ReviewQueueMetricCard(systemImage: "crown", title: "Largest", value: report.largestGroupName, detail: report.largestGroupBytes, color: .green)
        }
    }
}

struct AppReviewSafetyStrip: View {
    let report: AppReviewReport

    var body: some View {
        SectionBox(title: "Safety Boundaries") {
            LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, alignment: .leading, spacing: 10) {
                AppReviewSafetyPoint(systemImage: "lock.shield", title: "Related files stay review-only", detail: "Support data can contain licenses, plugins, state, and projects.")
                AppReviewSafetyPoint(systemImage: "questionmark.folder", title: "Orphans are heuristic", detail: "No app match is not proof that data is safe to delete.")
                AppReviewSafetyPoint(systemImage: "music.note", title: "Creative assets protected", detail: "GarageBand, Logic, and personal media remain preserve-first.")
            }

            if !report.notes.isEmpty {
                Text(report.notes.first ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AppReviewSafetyPoint: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AppReviewWorkspace: View {
    let report: AppReviewReport
    @Binding var selectedGroupID: String?
    let isWorking: Bool
    let onPreviewUninstall: (AppReviewGroup) -> Void
    @State private var filterText = ""

    private var groups: [AppReviewGroup] {
        report.allReviewGroups
    }

    private var selectedGroup: AppReviewGroup? {
        if let selectedGroupID, let match = groups.first(where: { $0.id == selectedGroupID }) {
            return match
        }
        return groups.first
    }

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "No app-owned storage matched",
                systemImage: "app.dashed",
                description: Text("Try including orphan candidates or lowering the CLI threshold for a deeper app review.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    AppReviewGroupRail(
                        groups: groups,
                        selectedGroupID: activeGroupID,
                        filterText: $filterText,
                        onSelect: { selectedGroupID = $0.id }
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

                    if let selectedGroup {
                        AppReviewDetailPanel(
                            group: selectedGroup,
                            isWorking: isWorking,
                            onPreviewUninstall: onPreviewUninstall
                        )
                        .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    AppReviewGroupRail(
                        groups: groups,
                        selectedGroupID: activeGroupID,
                        filterText: $filterText,
                        onSelect: { selectedGroupID = $0.id }
                    )

                    if let selectedGroup {
                        AppReviewDetailPanel(
                            group: selectedGroup,
                            isWorking: isWorking,
                            onPreviewUninstall: onPreviewUninstall
                        )
                    }
                }
            }
        }
    }

    private var activeGroupID: String? {
        selectedGroup?.id
    }
}

struct AppReviewGroupRail: View {
    let groups: [AppReviewGroup]
    let selectedGroupID: String?
    @Binding var filterText: String
    let onSelect: (AppReviewGroup) -> Void

    private var filteredGroups: [AppReviewGroup] {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return groups }
        return groups.filter { group in
            group.ownerName.localizedCaseInsensitiveContains(trimmed)
                || (group.bundleIdentifier?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (group.appPath?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        SectionBox(title: "App Groups") {
            VStack(alignment: .leading, spacing: 10) {
                searchField
                groupSection(title: "Installed apps", groups: filteredGroups.filter(\.isInstalled))
                groupSection(title: "Orphan candidates", groups: filteredGroups.filter { !$0.isInstalled })
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter apps", text: $filterText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private func groupSection(title: String, groups: [AppReviewGroup]) -> some View {
        if !groups.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ForEach(groups.prefix(28)) { group in
                Button {
                    onSelect(group)
                } label: {
                    AppReviewGroupRow(group: group, isSelected: selectedGroupID == group.id)
                }
                .buttonStyle(.plain)
            }

            if groups.count > 28 {
                Text("\(groups.count - 28) more group(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AppReviewGroupRow: View {
    let group: AppReviewGroup
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.isInstalled ? "app.dashed" : "questionmark.folder")
                .foregroundStyle(group.isInstalled ? .blue : .orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.ownerName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(group.bundleIdentifier ?? group.appPath ?? group.groupKindLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(group.items.count) item(s)")
                    Text(group.dominantCategory)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(ByteFormat.string(group.totalAllocatedSize))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                SafetyBadge(safetyClass: group.highestRiskClass)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.12), lineWidth: 1)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AppReviewDetailPanel: View {
    let group: AppReviewGroup
    let isWorking: Bool
    let onPreviewUninstall: (AppReviewGroup) -> Void

    var body: some View {
        SectionBox(title: "Selected App Review") {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                AppReviewDetailSummary(group: group)
                nextStep
                AppReviewFileTable(items: Array(group.items.prefix(12)))
                if group.items.count > 12 {
                    Text("\(group.items.count - 12) more related item(s) in this group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                AppReviewDetailFooter(group: group)
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                headerText
                Spacer()
                headerActions
            }

            VStack(alignment: .leading, spacing: 12) {
                headerText
                headerActions
            }
        }
    }

    private var headerText: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: group.isInstalled ? "app.dashed" : "questionmark.folder")
                .font(.title2)
                .foregroundStyle(group.isInstalled ? .blue : .orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.ownerName)
                    .font(.title2.bold())
                Text(group.bundleIdentifier ?? group.groupKindLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let appPath = group.appPath {
                    Text(appPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: 8) {
            ReviewQueueStatusPill(text: group.groupKindLabel, color: group.isInstalled ? .blue : .orange)
            SafetyBadge(safetyClass: group.highestRiskClass)
            if group.isInstalled {
                Button {
                    onPreviewUninstall(group)
                } label: {
                    Label("Preview Uninstall", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
                .help("Build a manual uninstall preview. This does not remove the app or related files.")
            }
        }
    }

    private var nextStep: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.isInstalled ? "shield.lefthalf.filled" : "questionmark.circle")
                .foregroundStyle(group.isInstalled ? .purple : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Recommended next step")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(group.recommendedNextAction.label)
                    .font(.headline)
                Text(group.recommendedNextAction.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill((group.isInstalled ? Color.purple : Color.orange).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke((group.isInstalled ? Color.purple : Color.orange).opacity(0.22), lineWidth: 1)
                )
        }
    }
}

struct AppReviewDetailSummary: View {
    let group: AppReviewGroup

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
            GridRow {
                summaryCell("Review bytes", ByteFormat.string(group.totalAllocatedSize))
                summaryCell("Related items", "\(group.items.count)")
                summaryCell("Dominant data", group.dominantCategory)
                summaryCell("Largest item", ByteFormat.string(group.items.first?.allocatedSize ?? 0))
            }
        }
    }

    private func summaryCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct AppReviewFileTableScrollContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(minWidth: 720, alignment: .leading)
        }
    }
}

struct AppReviewFileTable: View {
    let items: [AppReviewItem]

    var body: some View {
        AppReviewFileTableScrollContainer {
            AppReviewFileHeader()
            ForEach(items) { item in
                AppReviewFileRow(item: item)
            }
        }
    }
}

struct AppReviewFileHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("File").frame(maxWidth: .infinity, alignment: .leading)
            Text("Kind").frame(width: 96, alignment: .leading)
            Text("Next").frame(width: 126, alignment: .leading)
            Text("Size").frame(width: 86, alignment: .trailing)
            Text("Safety").frame(width: 136, alignment: .leading)
            Text("Actions").frame(width: 112, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}

struct AppReviewFileRow: View {
    let item: AppReviewItem

    var body: some View {
        Divider()
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                Text(item.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.category)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            Text(item.nextAction.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 126, alignment: .leading)
            Text(ByteFormat.string(item.allocatedSize))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 86, alignment: .trailing)
            SafetyBadge(safetyClass: item.safetyClass)
                .frame(width: 136, alignment: .leading)
            AppReviewItemActionButtons(item: item)
                .frame(width: 112, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}

struct AppReviewDetailFooter: View {
    let group: AppReviewGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Related files stay review-only from this report.", systemImage: "lock.shield")
            if group.isInstalled {
                Label("Preview Uninstall builds a receipt path for the app bundle only.", systemImage: "doc.text.magnifyingglass")
            } else {
                Label("Orphan status is a heuristic. Review in Finder before deciding anything.", systemImage: "questionmark.folder")
            }
            ForEach(group.notes.prefix(1), id: \.self) { note in
                Label(note, systemImage: "info.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppReviewSkippedPathsView: View {
    let report: AppReviewReport
    @Binding var showSkipped: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show skipped paths", isOn: $showSkipped)
                .toggleStyle(.switch)
            if showSkipped {
                SectionBox(title: "Skipped Or Excluded") {
                    if report.skipped.isEmpty {
                        Text("No skipped paths were reported.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(report.skipped.prefix(80), id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

struct AppReviewEmptyState: View {
    let isWorking: Bool
    let onReview: () -> Void

    var body: some View {
        SectionBox(title: "Start Review") {
            VStack(alignment: .leading, spacing: 12) {
                ContentUnavailableView(
                    "No app review yet",
                    systemImage: "app.dashed",
                    description: Text("Run an app review to group installed-app support files and possible orphan data by owner.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)

                Button(action: onReview) {
                    Label(isWorking ? "Reviewing" : "Review Apps", systemImage: "app.dashed")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
    }
}

private extension AppReviewReport {
    var allReviewGroups: [AppReviewGroup] {
        installedAppGroups + orphanGroups
    }

    var largestGroupName: String {
        largestGroup?.ownerName ?? "-"
    }

    var largestGroupBytes: String {
        guard let largestGroup else { return "no groups" }
        return ByteFormat.string(largestGroup.totalAllocatedSize)
    }

    private var largestGroup: AppReviewGroup? {
        allReviewGroups.max { lhs, rhs in
            lhs.totalAllocatedSize < rhs.totalAllocatedSize
        }
    }
}

private extension AppReviewGroup {
    var groupKindLabel: String {
        isInstalled ? "Installed app" : "Orphan candidate"
    }

    var dominantCategory: String {
        let counts = Dictionary(grouping: items, by: \.category)
            .mapValues { groupedItems in groupedItems.reduce(Int64(0)) { $0 + $1.allocatedSize } }
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key ?? "Mixed"
    }

    var recommendedNextAction: ReviewNextAction {
        if !isInstalled {
            return .reviewInFinder
        }
        switch highestRiskClass {
        case .neverTouch:
            return .doNotTouch
        case .preserveByDefault:
            return .protectByDefault
        case .autoSafe, .safeAfterCondition, .reviewRequired:
            return .reviewInFinder
        }
    }
}
