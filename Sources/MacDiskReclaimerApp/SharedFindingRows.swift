import SwiftUI
import ReclaimerCore

struct FindingRow: View {
    let finding: Finding

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(finding.displayName)
                    .lineLimit(1)
                Text(ByteFormat.string(finding.allocatedSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SafetyBadge(safetyClass: finding.safetyClass)
        }
    }
}

struct ReviewSummaryList: View {
    let title: String
    let summaries: [BucketSummary]

    var body: some View {
        SectionBox(title: title) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summaries) { summary in
                    HStack {
                        Text(summary.name)
                            .lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(summary.allocatedSize))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            .frame(minWidth: 180)
        }
    }
}

struct TopOffenderTableScrollContainer<Rows: View>: View {
    var includesDetailAction = false
    @ViewBuilder let rows: Rows

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                TopOffenderHeader(includesDetailAction: includesDetailAction)
                rows
            }
            .frame(minWidth: RyddiWindowLayout.topOffenderTableMinimumWidth, alignment: .leading)
        }
    }
}

struct TopOffenderHeader: View {
    var includesDetailAction = false

    var body: some View {
        HStack {
            Text("Reclaim").frame(width: 86, alignment: .leading)
            Text("Size").frame(width: 86, alignment: .leading)
            Text("Confidence").frame(width: 92, alignment: .leading)
            Text("Safety").frame(width: 150, alignment: .leading)
            Text("Category").frame(width: 130, alignment: .leading)
            Text("Owner").frame(width: 110, alignment: .leading)
            Text("Next").frame(width: 124, alignment: .leading)
            Text("Age").frame(width: 48, alignment: .leading)
            Text("Path")
            Spacer()
            Text("Actions").frame(width: includesDetailAction ? 164 : 132, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}

struct TopOffenderRowView: View {
    let row: TopOffenderRow
    let isSelectedInPlan: Bool
    let onOpenDetail: ((Finding) -> Void)?

    init(
        row: TopOffenderRow,
        isSelectedInPlan: Bool,
        onOpenDetail: ((Finding) -> Void)? = nil
    ) {
        self.row = row
        self.isSelectedInPlan = isSelectedInPlan
        self.onOpenDetail = onOpenDetail
    }

    var body: some View {
        Divider()
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormat.string(row.estimatedImmediateReclaim))
                    .foregroundStyle(row.estimatedImmediateReclaim > 0 ? .green : .secondary)
                Text(row.reclaimabilityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormat.string(row.allocatedSize))
                Text(ByteFormat.string(row.logicalSize))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.confidence.label)
                    .foregroundStyle(confidenceColor)
                if isSelectedInPlan {
                    Text("In plan")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 92, alignment: .leading)
            SafetyBadge(safetyClass: row.safetyClass)
                .frame(width: 150, alignment: .leading)
            Text(row.category)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
            Text(row.ownerName)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            Text(row.nextAction.label)
                .font(.caption)
                .foregroundStyle(nextActionColor)
                .frame(width: 124, alignment: .leading)
                .lineLimit(1)
            Text(row.ageDays.map { "\($0)d" } ?? "-")
                .frame(width: 48, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .lineLimit(1)
                Text(row.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                if let onOpenDetail {
                    Button {
                        onOpenDetail(row.finding)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .help("Open evidence detail")
                }
                FindingActionButtons(finding: row.finding)
            }
            .buttonStyle(.borderless)
            .frame(width: onOpenDetail == nil ? 132 : 164, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    private var confidenceColor: Color {
        switch row.confidence {
        case .high: .green
        case .conditional: .blue
        case .review: .orange
        case .protected: .purple
        case .blocked: .red
        }
    }

    private var nextActionColor: Color {
        switch row.nextAction {
        case .safeMaintenance: .green
        case .quitAppFirst: .orange
        case .useNativeTool: .blue
        case .reviewInFinder, .archiveCandidate: .secondary
        case .protectByDefault, .doNotTouch: .red
        }
    }
}

struct FindingActionButtons: View {
    let finding: Finding

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(finding.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(finding.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(finding.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: finding.path, isDirectory: finding.isDirectory)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct DuplicateFileActionButtons: View {
    let file: DuplicateFile

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(file.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(file.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(file.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: file.path, isDirectory: false)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct AppReviewItemActionButtons: View {
    let item: AppReviewItem

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(item.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(item.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(item.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: item.path, isDirectory: item.isDirectory)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct DownloadsReviewItemActionButtons: View {
    let item: DownloadsReviewItem

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(item.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(item.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(item.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: item.path, isDirectory: item.isDirectory)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct AppUninstallCandidateActionButtons: View {
    let candidate: AppUninstallCandidate

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(candidate.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(candidate.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(candidate.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: candidate.path, isDirectory: candidate.isDirectory)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct SafetyBadge: View {
    let safetyClass: SafetyClass

    var body: some View {
        Text(safetyClass.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch safetyClass {
        case .autoSafe: .green
        case .safeAfterCondition: .blue
        case .reviewRequired: .orange
        case .preserveByDefault: .purple
        case .neverTouch: .red
        }
    }
}

struct SectionBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
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
}
