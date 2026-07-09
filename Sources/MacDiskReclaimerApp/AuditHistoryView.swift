import SwiftUI
import ReclaimerCore

struct AuditHistoryView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Audit History")
                    .font(.largeTitle.bold())
                Text("Local-only saved plans and execution receipts. Empty history is normal until a plan or dry run is saved.")
                    .foregroundStyle(.secondary)

                SectionBox(title: "Audit Store Hygiene") {
                    if let summary = model.auditStoreSummary {
                        HStack(spacing: 12) {
                            MetricTile(title: "Known files", value: "\(summary.totalKnownFileCount)")
                            MetricTile(title: "Known size", value: ByteFormat.string(summary.totalKnownBytes))
                            MetricTile(title: "Unknown", value: "\(summary.unknownFileCount)")
                            MetricTile(title: "Symlinks", value: "\(summary.symlinkCount)")
                        }
                        Text(summary.rootPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    } else {
                        Text("Audit summary has not loaded yet.")
                    }
                    Text("Pruning is never scheduled. Preview first; only known Ryddi audit JSON files are candidates, and symlinks or unknown files are skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Preview Prune") {
                            model.previewAuditPrune()
                        }
                        Button("Delete Previewed Audit Files") {
                            model.confirmAuditPrune()
                        }
                        .disabled(model.auditPrunePlan?.candidates.isEmpty != false)
                    }
                    if let plan = model.auditPrunePlan {
                        Text("Preview: \(plan.candidateCount) candidate(s), \(ByteFormat.string(plan.candidateBytes)). Policy: older than \(plan.policy.olderThanDays) days, keep \(plan.policy.keepRecent) recent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let receipt = model.auditPruneReceipt {
                        Text("\(receipt.dryRun ? "Dry-run" : "Prune") receipt: \(receipt.deletedCount) deleted, \(ByteFormat.string(receipt.deletedBytes)), \(receipt.errors.count) error(s).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SectionBox(title: "Recent Plans") {
                    if model.recentPlans.isEmpty {
                        Text("No saved plans yet.")
                    } else {
                        if let url = model.lastPlanReportExportURL {
                            Text("Latest plan report: \(url.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        ForEach(model.recentPlans) { plan in
                            HStack {
                                Text("\(plan.createdAt.formatted()) - \(plan.items.filter(\.selected).count) selected - \(ByteFormat.string(plan.expectedImmediateReclaim))")
                                Spacer()
                                Button("Export") {
                                    Task { await model.exportPlanReport(plan) }
                                }
                                Button("Redacted") {
                                    Task { await model.exportPlanReport(plan, pathStyle: .redacted) }
                                }
                            }
                        }
                    }
                }

                SectionBox(title: "Recent Receipts") {
                    if model.recentReceipts.isEmpty {
                        Text("No receipts yet.")
                    } else {
                        if let url = model.lastReceiptReportExportURL {
                            Text("Latest receipt report: \(url.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        ForEach(model.recentReceipts) { receipt in
                            HStack {
                                Text("\(receipt.createdAt.formatted()) - \(receipt.mode) - \(receipt.actions.count) actions")
                                Spacer()
                                Button("Export") {
                                    Task { await model.exportReceiptReport(receipt) }
                                }
                                Button("Redacted") {
                                    Task { await model.exportReceiptReport(receipt, pathStyle: .redacted) }
                                }
                            }
                        }
                    }
                }

                SectionBox(title: "Native Tool Reports") {
                    if model.recentNativeToolReports.isEmpty {
                        Text("No native-tool reports yet.")
                    } else {
                        ForEach(model.recentNativeToolReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.receipts.count) candidate(s) - \(ByteFormat.string(report.totalBytesUnderNativeReview))")
                        }
                    }
                }

                SectionBox(title: "Native Command Receipts") {
                    if model.recentNativeToolExecutionReceipts.isEmpty {
                        Text("No native command receipts yet.")
                    } else {
                        ForEach(model.recentNativeToolExecutionReceipts) { receipt in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(receipt.createdAt.formatted()) - \(receipt.status) - \(receipt.command.id)")
                                    Spacer()
                                    Text(receipt.mode.rawValue)
                                        .foregroundStyle(.secondary)
                                }
                                Text(receipt.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                                    GridRow {
                                        Text("Command")
                                            .foregroundStyle(.secondary)
                                        Text(receipt.command.command)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }
                                    GridRow {
                                        Text("Path")
                                            .foregroundStyle(.secondary)
                                        Text(receipt.findingPath)
                                            .font(.caption.monospaced())
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                    }
                                    GridRow {
                                        Text("Risk")
                                            .foregroundStyle(.secondary)
                                        Text(receipt.command.risk.label)
                                    }
                                    if let before = receipt.beforeFreeBytes {
                                        GridRow {
                                            Text("Before")
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(before))
                                                .monospacedDigit()
                                        }
                                    }
                                    if let after = receipt.afterFreeBytes {
                                        GridRow {
                                            Text("After")
                                                .foregroundStyle(.secondary)
                                            Text(ByteFormat.string(after))
                                                .monospacedDigit()
                                        }
                                    }
                                }
                                .font(.caption)
                                if let output = receipt.output {
                                    if !output.stdoutPreview.isEmpty {
                                        Text("stdout: \(output.stdoutPreview.prefix(3).joined(separator: " | "))")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .textSelection(.enabled)
                                    }
                                    if !output.stderrPreview.isEmpty {
                                        Text("stderr: \(output.stderrPreview.prefix(3).joined(separator: " | "))")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .textSelection(.enabled)
                                    }
                                }
                                if !receipt.errors.isEmpty {
                                    Text("Errors: \(receipt.errors.joined(separator: " | "))")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let note = receipt.nonClaims.first {
                                    Text("Non-claim: \(note)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                SectionBox(title: "Container Inventory Reports") {
                    if model.recentContainerInventoryReports.isEmpty {
                        Text("No container inventory reports yet.")
                    } else {
                        ForEach(model.recentContainerInventoryReports) { report in
                            let reclaim = report.dockerReclaimableBytes.map(ByteFormat.string) ?? "unknown reclaim"
                            Text("\(report.createdAt.formatted()) - Docker \(report.docker.status.state.label), Colima \(report.colima.status.state.label) - \(reclaim)")
                        }
                    }
                }

                SectionBox(title: "Active File Reports") {
                    if model.recentActiveFileReviewReports.isEmpty {
                        Text("No active-file reports yet.")
                    } else {
                        ForEach(model.recentActiveFileReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.openCount) open - \(report.failedCheckCount) failed - \(ByteFormat.string(report.totalBlockedBytes))")
                        }
                    }
                }

                SectionBox(title: "Trash Review Reports") {
                    if model.recentTrashReviewReports.isEmpty {
                        Text("No Trash review reports yet.")
                    } else {
                        ForEach(model.recentTrashReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.permissionState.rawValue) - \(report.itemCount) item(s) - \(ByteFormat.string(report.totalAllocatedSize))")
                        }
                    }
                }

                SectionBox(title: "Downloads Review Reports") {
                    if model.recentDownloadsReviewReports.isEmpty {
                        Text("No Downloads review reports yet.")
                    } else {
                        ForEach(model.recentDownloadsReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.permissionState.rawValue) - \(report.displayedItemCount) shown - \(ByteFormat.string(report.reviewCandidateBytes)) candidates")
                        }
                    }
                }

                SectionBox(title: "Browser Cache Review Reports") {
                    if model.recentBrowserCacheReviewReports.isEmpty {
                        Text("No browser cache review reports yet.")
                    } else {
                        ForEach(model.recentBrowserCacheReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.rootSummaries.count) root(s) - \(ByteFormat.string(report.candidateBytes)) candidates")
                        }
                    }
                }

                SectionBox(title: "Package Cache Review Reports") {
                    if model.recentPackageCacheReviewReports.isEmpty {
                        Text("No package cache review reports yet.")
                    } else {
                        ForEach(model.recentPackageCacheReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.rootSummaries.count) root(s) - \(ByteFormat.string(report.candidateBytes)) candidates")
                        }
                    }
                }

                SectionBox(title: "Project Dependency Review Reports") {
                    if model.recentProjectDependencyReviewReports.isEmpty {
                        Text("No project dependency review reports yet.")
                    } else {
                        ForEach(model.recentProjectDependencyReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.rootSummaries.count) root(s) - \(report.displayedItemCount) shown - \(ByteFormat.string(report.candidateBytes)) candidates")
                        }
                    }
                }

                SectionBox(title: "Device Backup Review Reports") {
                    if model.recentDeviceBackupReviewReports.isEmpty {
                        Text("No device backup review reports yet.")
                    } else {
                        ForEach(model.recentDeviceBackupReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.permissionState.rawValue) - \(report.backupCount) backup(s) - \(ByteFormat.string(report.totalAllocatedSize))")
                        }
                    }
                }

                SectionBox(title: "Xcode Review Reports") {
                    if model.recentXcodeReviewReports.isEmpty {
                        Text("No Xcode review reports yet.")
                    } else {
                        ForEach(model.recentXcodeReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.rootSummaries.count) root(s) - \(ByteFormat.string(report.rebuildableCacheBytes)) rebuildable - \(ByteFormat.string(report.reviewRequiredBytes)) review")
                        }
                    }
                }

                SectionBox(title: "App Uninstall Receipts") {
                    if model.recentAppUninstallReceipts.isEmpty {
                        Text("No app-uninstall receipts yet.")
                    } else {
                        ForEach(model.recentAppUninstallReceipts) { receipt in
                            Text("\(receipt.createdAt.formatted()) - \(receipt.mode) - \(receipt.status) - \(receipt.appDisplayName)")
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
