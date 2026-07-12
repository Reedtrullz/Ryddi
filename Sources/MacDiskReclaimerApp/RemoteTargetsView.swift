import SwiftUI
import ReclaimerCore

struct RemoteTargetsView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remote Targets")
                            .font(.largeTitle.bold())
                        Text("Agentless, report-only SSH evidence for VPS disk cleanup decisions.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.refreshRemoteTargets()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isWorking)
                }

                SectionBox(title: "Target") {
                    TextField("SSH alias or host", text: Binding(
                        get: { model.remoteTargetInput },
                        set: { model.remoteTargetInput = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    if !model.remoteTargets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(model.remoteTargets) { target in
                                    Button(target.input) {
                                        model.remoteTargetInput = target.input
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    HStack {
                        Button {
                            Task { await model.probeRemoteTarget() }
                        } label: {
                            Label("Probe", systemImage: "network")
                        }
                        .disabled(model.remoteTargetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
                        .accessibilityIdentifier("remote-targets.probe-button")

                        Button {
                            Task { await model.scanRemoteTarget() }
                        } label: {
                            Label("Scan", systemImage: "externaldrive")
                        }
                        .disabled(model.remoteTargetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
                        .accessibilityIdentifier("remote-targets.scan-button")

                        Button {
                            Task { await model.exportRemoteRedactedReport() }
                        } label: {
                            Label("Export Redacted", systemImage: "eye.slash")
                        }
                        .disabled(model.remoteScanReport == nil || model.isWorking)
                        .accessibilityIdentifier("remote-targets.export-redacted-button")

                        Button {
                            Task { await model.exportRemoteRedactedGrowthReport() }
                        } label: {
                            Label("Export Growth", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        .disabled(model.remoteGrowthReport == nil || model.isWorking)

                        Button {
                            Task { await model.exportRemoteDogfoodReportFromAudit() }
                        } label: {
                            Label("Dogfood Report", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(model.recentRemoteScanReports.isEmpty || model.isWorking)
                    }
                }

                if model.isWorking {
                    ProgressView("Running read-only remote check...")
                }

                if let probe = model.remoteProbeReport {
                    HStack(spacing: 16) {
                        MetricTile(title: "Connection", value: probe.commands.contains { $0.exitCode == 0 } ? "Reached" : "No response")
                        MetricTile(title: "Host key", value: probe.target.knownHostsState)
                        MetricTile(title: "OS", value: probe.osSummary ?? "Unknown")
                        MetricTile(title: "Tools", value: "\(probe.availableTools.count)")
                    }

                    SectionBox(title: "Connection Evidence") {
                        Text("Target: \(probe.target.alias ?? probe.target.input)")
                        Text("Host: \(probe.target.resolvedHost ?? "unknown")")
                        Text("User: \(probe.target.resolvedUser ?? "unknown")")
                        Text("Home: \(probe.homeDirectory ?? "unknown")")
                        if let sudo = probe.sudoNonInteractive {
                            Text("Non-interactive sudo: \(sudo ? "available" : "not available")")
                        }
                    }
                }

                if let report = model.remoteScanReport {
                    HStack(spacing: 16) {
                        MetricTile(title: "Disk pressure", value: remotePressureLabel(report.diskFilesystems))
                        MetricTile(title: "Inode pressure", value: remotePressureLabel(report.inodeFilesystems))
                        MetricTile(title: "Findings", value: "\(report.findings.count)")
                        MetricTile(title: "Native guidance", value: "\(report.nativeGuidance.count)")
                    }

                    SectionBox(title: "Remote Safety") {
                        let commandIssues = report.commands.filter { $0.exitCode != 0 || $0.timedOut }.count
                        HStack(spacing: 16) {
                            MetricTile(title: "Mode", value: "Report-only")
                            MetricTile(title: "Cleanup", value: "None")
                            MetricTile(title: "Coverage", value: report.coverage.level.rawValue.capitalized)
                            MetricTile(title: "Command issues", value: "\(commandIssues)")
                            MetricTile(title: "Path privacy", value: report.findings.contains { $0.displayPath.contains("redacted") } ? "Redacted" : "Full")
                        }
                        Text(report.coverage.explanation)
                            .font(.caption)
                            .foregroundStyle(report.coverage.level == .complete ? Color.secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if !report.coverage.rows.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(report.coverage.rows) { row in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Circle()
                                            .fill(remoteCoverageStatusColor(row.status))
                                            .frame(width: 7, height: 7)
                                        Text(row.label)
                                            .font(.caption.weight(.semibold))
                                        Text(row.status.rawValue.capitalized)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(remoteCoverageStatusColor(row.status))
                                        Spacer(minLength: 8)
                                        Text(row.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        Text(commandIssues == 0 ? "All read-only commands returned usable evidence." : "Some read-only commands failed or were unavailable; do not treat missing evidence as clean.")
                            .font(.caption)
                            .foregroundStyle(commandIssues == 0 ? Color.secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if !report.continuityWarnings.isEmpty {
                            ForEach(report.continuityWarnings) { warning in
                                Text("\(warning.field.capitalized) changed: \(warning.previousValue) -> \(warning.currentValue)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ForEach(report.nonClaims.prefix(2), id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SectionBox(title: "Review Queues") {
                        let grouped = Dictionary(grouping: report.findings, by: \.recommendedNextAction)
                        ForEach(grouped.keys.sorted { $0.label < $1.label }, id: \.self) { action in
                            let rows = grouped[action] ?? []
                            HStack {
                                Text(action.label)
                                    .frame(width: 150, alignment: .leading)
                                Text("\(rows.count) item(s)")
                                    .frame(width: 90, alignment: .leading)
                                Text(ByteFormat.string(rows.compactMap(\.allocatedBytes).reduce(0, +)))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }

                    SectionBox(title: "Top Remote Findings") {
                        ForEach(report.findings.sorted(by: { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }).prefix(12)) { finding in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(finding.bucket)
                                        .font(.headline)
                                    Spacer()
                                    Text(finding.allocatedBytes.map(ByteFormat.string) ?? "Unknown")
                                    Text(finding.safetyClass.label)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.quaternary.opacity(0.4))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                Text(finding.displayPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                                Text(finding.recommendedNextAction.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }

                    SectionBox(title: "Native Guidance") {
                        if report.nativeGuidance.isEmpty {
                            Text("No native guidance generated.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.nativeGuidance) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.headline)
                                    Text(item.command)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                    Text(item.summary)
                                        .foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Manual Command Cards") {
                        if report.commandCards.isEmpty {
                            Text("No manual command cards generated.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.commandCards) { card in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(card.title)
                                                .font(.headline)
                                            HStack(spacing: 8) {
                                                Text(card.kind.label)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.blue)
                                                Text(card.risk.label)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(card.risk == .preserveByDefault ? .purple : .orange)
                                            }
                                        }
                                        Spacer()
                                        Button {
                                            PathActions.copyText(card.displayCommand)
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    Text(card.displayCommand)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                    Text(card.explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(card.prerequisites.prefix(3), id: \.self) { prerequisite in
                                        Text("• \(prerequisite)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Divider()
                            }
                            Text("Ryddi never runs these commands remotely. Copy one only after reviewing service impact.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let dogfood = model.currentRemoteDogfoodReport {
                        SectionBox(title: "Dogfood Evidence") {
                            HStack(spacing: 16) {
                                MetricTile(title: "Findings", value: "\(dogfood.findingCount)")
                                MetricTile(title: "Finding bytes", value: ByteFormat.string(dogfood.totalFindingBytes))
                                MetricTile(title: "Commands", value: "\(dogfood.commandResults.count)")
                                MetricTile(title: "Disk pressure", value: dogfood.diskPressureSummary)
                            }
                            Text("Target: \(dogfood.target.alias ?? dogfood.target.input)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Built from read-only remote evidence. It does not run cleanup or reconnect when exported from saved audit.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(dogfood.nonClaims.prefix(5), id: \.self) { note in
                                Text("• \(note)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let growth = model.remoteGrowthReport {
                        SectionBox(title: "Saved Growth") {
                            HStack(spacing: 16) {
                                MetricTile(title: "Saved scans", value: "\(growth.previousFindingCount) -> \(growth.currentFindingCount)")
                                MetricTile(title: "Finding bytes", value: remoteSignedBytes(growth.deltaAllocatedBytes))
                                MetricTile(title: "Buckets", value: "\(growth.bucketDeltas.count)")
                                MetricTile(title: "Path deltas", value: "\(growth.findingDeltas.count)")
                            }
                            Text("Compares saved local remote scan audit records only. It does not reconnect to the host or prove current server state.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !growth.bucketDeltas.isEmpty {
                                Text("Largest bucket deltas")
                                    .font(.headline)
                                ForEach(growth.bucketDeltas.prefix(6)) { delta in
                                    HStack {
                                        Text(delta.bucket)
                                        Spacer()
                                        Text(remoteSignedBytes(delta.deltaAllocatedBytes))
                                            .foregroundStyle(delta.deltaAllocatedBytes >= 0 ? .orange : .secondary)
                                    }
                                }
                            }
                            if !growth.findingDeltas.isEmpty {
                                Text("Largest path deltas")
                                    .font(.headline)
                                ForEach(growth.findingDeltas.prefix(6)) { delta in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(remoteSignedBytes(delta.deltaAllocatedBytes))
                                                .font(.caption.weight(.semibold))
                                            Text(delta.bucket)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                        }
                                        Text(delta.displayPath)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }

                    SectionBox(title: "Command Receipts") {
                        ForEach(report.commands, id: \.commandID) { command in
                            RemoteCommandOutcomeRow(command: command)
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text("- \(note)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView("No remote scan yet", systemImage: "network", description: Text("Probe or scan an SSH target to collect read-only VPS storage evidence."))
                }

                if let url = model.lastRemoteReportExportURL {
                    Text("Last remote export: \(url.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let url = model.lastRemoteGrowthReportExportURL {
                    Text("Last remote growth export: \(url.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let url = model.lastRemoteDogfoodReportExportURL {
                    Text("Last remote dogfood export: \(url.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }

    private func remotePressureLabel(_ filesystems: [RemoteFilesystemSummary]) -> String {
        let maxPressure = filesystems.compactMap(\.capacityPercent).max()
        return maxPressure.map { "\($0)%" } ?? "Unknown"
    }

    private func remoteSignedBytes(_ bytes: Int64) -> String {
        bytes > 0 ? "+\(ByteFormat.string(bytes))" : ByteFormat.string(bytes)
    }

    private func remoteCoverageStatusColor(_ status: RemoteCoverageRowStatus) -> Color {
        switch status {
        case .passed:
            .green
        case .warning:
            .orange
        case .failed:
            .red
        case .unknown:
            .secondary
        }
    }
}

struct RemoteCommandOutcomeRow: View {
    let command: RemoteCommandResult

    var body: some View {
        let exitText = command.exitCode.map(String.init) ?? "blocked"
        VStack(alignment: .leading, spacing: 3) {
            Text(command.displayCommand)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text("exit \(exitText)")
                .font(.caption)
                .foregroundStyle(command.exitCode == 0 ? Color.secondary : Color.orange)
            if let stderr = command.stderrPreview.first {
                Text(stderr)
                    .foregroundStyle(.secondary)
            } else if let stdout = command.stdoutPreview.first {
                Text(stdout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
