import SwiftUI
import ReclaimerCore

struct FindingDetailView: View {
    let model: DashboardModel
    let finding: Finding
    let planItem: ReclaimPlanItem?
    @State private var pendingNativeCommand: NativeToolCommand?

    private var explanation: FindingExplanationReport {
        FindingExplanationBuilder.build(for: finding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(finding.displayName)
                    .font(.largeTitle.bold())
                Text(finding.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    SafetyBadge(safetyClass: finding.safetyClass)
                    Text(finding.actionKind.label)
                    Text(ByteFormat.string(finding.allocatedSize))
                    Text(finding.reviewNextAction.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                SectionBox(title: "Summary") {
                    Text(explanation.summary)
                    Text(explanation.cleanupPermission)
                        .foregroundStyle(.secondary)
                    Text(explanation.removalEffect)
                        .foregroundStyle(.secondary)
                }

                SectionBox(title: "What this is") {
                    ForEach(explanation.whatThisIs, id: \.self) { line in
                        Text(line)
                            .foregroundStyle(line.hasPrefix("Accounting") ? Color.secondary : Color.primary)
                    }
                }

                SectionBox(title: "Actions") {
                    FindingActionButtons(finding: finding)
                }

                SectionBox(title: "Why this classification") {
                    ForEach(explanation.whyMatched, id: \.self) { line in
                        Text("- \(line)")
                    }
                }

                SectionBox(title: "Risk and exact action") {
                    Text(explanation.riskSummary)
                    Text(explanation.exactAction)
                    Text(explanation.cleanupPermission)
                        .foregroundStyle(.secondary)
                }

                SectionBox(title: "Recovery and conditions") {
                    ForEach(explanation.recovery, id: \.self) { line in
                        Text(line)
                    }
                    if !explanation.conditions.isEmpty {
                        Divider()
                    }
                    ForEach(explanation.conditions, id: \.self) { line in
                        Text("- \(line)")
                            .foregroundStyle(.secondary)
                    }
                }

                if let nativeReceipt = explanation.nativeToolReceipt {
                    SectionBox(title: "Native tool receipt preview") {
                        Text(nativeReceipt.message)
                            .foregroundStyle(.secondary)
                        ForEach(nativeReceipt.commands) { command in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(command.command)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("\(command.risk.label) • \(command.requiresReview ? "review first" : "inspect")")
                                    .font(.caption)
                                    .foregroundStyle(command.risk == .destructive ? .red : .secondary)
                                Text(command.purpose)
                                Text("Expected effect: \(command.expectedEffect)")
                                    .foregroundStyle(.secondary)
                                if let workingDirectory = command.workingDirectory {
                                    Text("Working directory: \(workingDirectory)")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
	                                if let context = command.context {
	                                    Text(context)
	                                        .foregroundStyle(.secondary)
	                                }
	                                let performBlockReason = model.nativePerformBlockReason(receipt: nativeReceipt, command: command)
	                                HStack {
	                                    Button {
	                                        Task { await model.runNativeToolCommand(receipt: nativeReceipt, command: command, perform: false) }
	                                    } label: {
	                                        Label("Dry Run", systemImage: "doc.text.magnifyingglass")
	                                    }
	                                    if performBlockReason == nil {
	                                        Button {
	                                            pendingNativeCommand = command
	                                        } label: {
                                            Label("Preview + Run", systemImage: "terminal")
	                                        }
	                                    }
	                                }
	                                if let performBlockReason {
	                                    Text(performBlockReason)
	                                        .font(.caption)
	                                        .foregroundStyle(.secondary)
	                                        .fixedSize(horizontal: false, vertical: true)
	                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    if !explanation.guidanceCommands.isEmpty {
                        SectionBox(title: "Guidance") {
                            ForEach(explanation.guidanceCommands, id: \.self) { line in
                                Text(line)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                SectionBox(title: "Next steps") {
                    ForEach(explanation.nextSteps, id: \.self) { line in
                        Text(line)
                    }
                    Divider()
                    ForEach(explanation.nonClaims, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let planItem {
                    SectionBox(title: "Plan status") {
                        Text(planItem.selected ? "Selected for dry-run/action." : "Not selected automatically.")
                        Text("Estimated immediate reclaim: \(ByteFormat.string(planItem.estimatedImmediateReclaim))")
                        ForEach(planItem.conditions, id: \.message) { condition in
                            Text("\(condition.isSatisfied ? "OK" : "Blocked"): \(condition.message)")
                                .foregroundStyle(condition.isSatisfied ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
            .padding(24)
        }
        .confirmationDialog(
            "Preview and run native command?",
            isPresented: Binding(
                get: { pendingNativeCommand != nil },
                set: { if !$0 { pendingNativeCommand = nil } }
            ),
            presenting: pendingNativeCommand
        ) { command in
            Button("Preview + Run \(command.command)", role: .destructive) {
                if let nativeReceipt = explanation.nativeToolReceipt {
                    Task { await model.runNativeToolCommand(receipt: nativeReceipt, command: command, perform: true) }
                }
                pendingNativeCommand = nil
            }
            Button("Cancel", role: .cancel) {
                pendingNativeCommand = nil
            }
        } message: { command in
            Text("Ryddi will run a fresh same-process preview before executing this native-tool command and save both receipts: \(command.command)")
        }
    }
}
