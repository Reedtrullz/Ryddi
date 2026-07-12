import SwiftUI
import ReclaimerCore

struct LargeOldReviewView: View {
    let model: DashboardModel

    private var report: LargeOldReviewReport? {
        model.presentationSnapshot?.largeOldReview
    }

    private var archiveReport: ArchiveReviewReport? {
        model.presentationSnapshot?.archiveReview
    }

    var body: some View {
        LargeOldReviewScrollContainer {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Large & Old Files")
                        .font(.largeTitle.bold())
                    Spacer()
                    Picker("Mode", selection: Binding(
                        get: { model.presentationLargeOldMode },
                        set: { mode in
                            Task {
                                await model.setLargeOldPresentation(
                                    mode: mode,
                                    sort: model.presentationLargeOldSort
                                )
                            }
                        }
                    )) {
                        ForEach(LargeOldReviewMode.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    Picker("Sort", selection: Binding(
                        get: { model.presentationLargeOldSort },
                        set: { sort in
                            Task {
                                await model.setLargeOldPresentation(
                                    mode: model.presentationLargeOldMode,
                                    sort: sort
                                )
                            }
                        }
                    )) {
                        Text("Allocated").tag(TopOffenderSort.allocated)
                        Text("Logical").tag(TopOffenderSort.logical)
                        Text("Age").tag(TopOffenderSort.age)
                        Text("Category").tag(TopOffenderSort.category)
                        Text("Owner").tag(TopOffenderSort.owner)
                        Text("Safety").tag(TopOffenderSort.safety)
                    }
                    .pickerStyle(.menu)
                }

                if let report {
                    HStack(spacing: 12) {
                        MetricTile(title: "Items", value: "\(report.totalCount)")
                        MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                        MetricTile(title: "Large", value: "\(report.largeCount)")
                        MetricTile(title: "Old", value: "\(report.oldCount)")
                        MetricTile(title: "Protected", value: ByteFormat.string(report.protectedBytes))
                    }
                }

                if model.findings.isEmpty {
                    ContentUnavailableView("No scan yet", systemImage: "doc.text.magnifyingglass", description: Text("Run Scan to build a large and old file review."))
                } else if report?.rows.isEmpty != false {
                    ContentUnavailableView("No large or old review rows", systemImage: "checkmark.circle", description: Text("No current findings matched the selected review mode."))
                } else if let report, let archiveReport {
                    HStack(alignment: .top, spacing: 14) {
                        ReviewSummaryList(title: "Signals", summaries: report.kindSummaries)
                        ReviewSummaryList(title: "Categories", summaries: Array(report.categorySummaries.prefix(6)))
                        ReviewSummaryList(title: "Safety", summaries: report.safetySummaries)
                    }

                    ArchiveCandidatePanel(
                        report: archiveReport,
                        onExport: { Task { await model.exportArchiveReview(mode: model.presentationLargeOldMode, sort: model.presentationLargeOldSort) } },
                        onExportRedacted: { Task { await model.exportArchiveReview(mode: model.presentationLargeOldMode, sort: model.presentationLargeOldSort, pathStyle: .redacted) } }
                    )

                    if let url = model.lastArchiveReviewExportURL {
                        Text("Latest archive review: \(url.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    SectionBox(title: "Review Rows") {
                        TopOffenderTableScrollContainer {
                            ForEach(report.rows) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    TopOffenderRowView(row: row.row, isSelectedInPlan: false)
                                    Text(row.reviewReason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 10)
                                }
                            }
                        }
                    }
                }

                if let report {
                    SectionBox(title: "Non-Claims") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.nonClaims, id: \.self) { note in
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct LargeOldReviewScrollContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
        }
    }
}

struct ArchiveCandidatePanel: View {
    let report: ArchiveReviewReport
    let onExport: () -> Void
    let onExportRedacted: () -> Void

    var body: some View {
        SectionBox(title: "Archive Candidates") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MetricTile(title: "Candidates", value: "\(report.candidateCount)")
                    MetricTile(title: "Archive", value: ByteFormat.string(report.archiveCandidateBytes))
                    MetricTile(title: "Trash Review", value: ByteFormat.string(report.trashReviewBytes))
                    MetricTile(title: "Cleanup Plan", value: ByteFormat.string(report.cleanupPlanBytes))
                    MetricTile(title: "Blocked", value: ByteFormat.string(report.blockedBytes))
                }

                HStack {
                    ForEach(report.recommendationSummaries.prefix(6)) { summary in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.name)
                                .font(.caption.weight(.semibold))
                            Text("\(summary.count) item(s), \(ByteFormat.string(summary.allocatedSize))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 110, alignment: .leading)
                    }
                    Spacer()
                    Button {
                        onExport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        onExportRedacted()
                    } label: {
                        Label("Redacted", systemImage: "eye.slash")
                    }
                }

                if report.rows.isEmpty {
                    Text("No archive candidates matched the selected large/old review mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Recommendation").frame(width: 120, alignment: .leading)
                            Text("Size").frame(width: 86, alignment: .leading)
                            Text("Age").frame(width: 48, alignment: .leading)
                            Text("Safety").frame(width: 150, alignment: .leading)
                            Text("Path")
                            Spacer()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        ForEach(report.rows.prefix(8)) { row in
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.recommendation.label)
                                        .frame(width: 120, alignment: .leading)
                                    Text(ByteFormat.string(row.allocatedSize))
                                        .frame(width: 86, alignment: .leading)
                                    Text(row.ageDays.map { "\($0)d" } ?? "-")
                                        .frame(width: 48, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    SafetyBadge(safetyClass: row.safetyClass)
                                        .frame(width: 150, alignment: .leading)
                                    Text(row.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                    Spacer()
                                }
                                Text(row.rationale)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                ForEach(report.nonClaims.prefix(2), id: \.self) { note in
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
