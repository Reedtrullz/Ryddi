import SwiftUI
import ReclaimerCore

struct PermissionOnboardingView: View {
    let model: DashboardModel

    private var walkthrough: PermissionWalkthrough {
        PermissionWalkthroughBuilder.build(report: model.permissionReport)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Permissions")
                    .font(.largeTitle.bold())
                Text("Ryddi verifies each configured scope with a metadata check, discarded directory listing, or read-only file open. These results describe those operations, not a Full Disk Access toggle.")
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                    MetricTile(title: "Coverage", value: model.permissionReport.coverageLevel.label)
                    MetricTile(title: "Access verified", value: "\(model.permissionReport.readableCount)")
                    MetricTile(title: "Permission required", value: "\(model.permissionReport.deniedCount)")
                    MetricTile(title: "Unavailable on this Mac", value: "\(model.permissionReport.missingCount)")
                    MetricTile(title: "Check failed", value: "\(model.permissionReport.unknownCount)")
                }

                PermissionAccessHelperPanel(
                    report: model.permissionReport,
                    onRefresh: { model.refreshPermissions() }
                )

                SectionBox(title: "Next Steps") {
                    ForEach(model.permissionReport.recommendedActions, id: \.self) { action in
                        Text(action)
                    }
                    if model.permissionReport.needsFullDiskAccessReview {
                        Button {
                            PathActions.openFullDiskAccessSettings()
                        } label: {
                            Label("Open Full Disk Access Settings", systemImage: "lock.shield")
                        }
                        .help("Open macOS Privacy & Security settings for Full Disk Access")
                    } else if model.permissionReport.missingCount > 0 {
                        Text("Unavailable optional paths need no System Settings change.")
                            .foregroundStyle(.secondary)
                    }
                }

                SectionBox(title: "First-run Walkthrough") {
                    ForEach(walkthrough.steps) { step in
                        PermissionWalkthroughStepRow(step: step)
                        if step.id != walkthrough.steps.last?.id {
                            Divider()
                        }
                    }
                }

                SectionBox(title: "Scope Readback") {
                    ForEach(model.permissionReport.scopeSummaries) { scope in
                        HStack(alignment: .firstTextBaseline) {
                            Text(scopeStatusLabel(scope.permissionState))
                                .font(.caption.bold())
                                .foregroundStyle(scopeStatusColor(scope.permissionState))
                                .frame(width: 142, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scope.name)
                                    .font(.headline)
                                Text(scope.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Text(scope.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let operation = scope.operation {
                                    Text(operationEvidence(scope, operation: operation))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if scope.permissionState == .unknown {
                                    Text("Refresh Access to retry this operation.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        Divider()
                    }
                }

                SectionBox(title: "Non-claims") {
                    ForEach(model.permissionReport.nonClaims, id: \.self) { note in
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private func scopeStatusLabel(_ state: PermissionState) -> String {
        switch state {
        case .readable: "Access verified"
        case .missing: "Unavailable on this Mac"
        case .denied: "Permission required"
        case .unknown: "Check failed"
        }
    }

    private func scopeStatusColor(_ state: PermissionState) -> Color {
        switch state {
        case .readable: .green
        case .missing: .secondary
        case .denied, .unknown: .orange
        }
    }

    private func operationEvidence(
        _ scope: ScopeAccessSummary,
        operation: ScopeAccessOperation
    ) -> String {
        var evidence = ["Operation: \(operationLabel(operation))."]
        if let errorCode = scope.errorCode {
            evidence.append("POSIX code: \(errorCode).")
        }
        if let detail = scope.detail {
            evidence.append(detail)
        }
        return evidence.joined(separator: " ")
    }

    private func operationLabel(_ operation: ScopeAccessOperation) -> String {
        switch operation {
        case .metadata: "Metadata"
        case .listDirectory: "Directory listing"
        case .openFile: "Read-only file open"
        }
    }
}
